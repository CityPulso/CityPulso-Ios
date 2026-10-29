import Alamofire
import Foundation

/** 请求体为空时用的占位类型（Retrofit 无 @Body 的接口）。 */
public struct EmptyBody: Encodable, Sendable {
    public init() {}
}

/**
 * 一个 HTTP 客户端（对应 Android Retrofit 实例 / WEB axios `publicClient` / `protectedClient`）：
 * - 路径相对 [PulsoCoreConfig.apiBaseURL]；wire 编解码统一走 [WireCoding]。
 * - 非 2xx 一律抛 [APIError]（带后端 errCode/message）。
 * - protected 客户端由 [ProtectedRequestInterceptor] 加 Bearer、处理 401 刷新重放。
 */
public struct APIClient: Sendable {
    /** Dev 远端 PG + 隧道偶发慢；详情页已并行请求，仍略放宽超时避免误杀。 */
    private static let timeout: TimeInterval = 12

    private let baseURL: URL
    private let session: Session

    public init(config: PulsoCoreConfig, interceptor: RequestInterceptor? = nil) {
        self.init(config: config, interceptor: interceptor, configuration: URLSessionConfiguration.af.default)
    }

    /** 测试用：注入带 stub `URLProtocol` 的 configuration。 */
    init(config: PulsoCoreConfig, interceptor: RequestInterceptor?, configuration: URLSessionConfiguration) {
        configuration.timeoutIntervalForRequest = Self.timeout
        baseURL = config.apiBaseURL
        session = Session(
            configuration: configuration,
            interceptor: interceptor,
            eventMonitors: config.debugHttpLogging ? [HTTPLogMonitor()] : []
        )
    }

    /** 带响应体的请求。 */
    public func request<Response: Decodable & Sendable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String?] = [:],
        headers: [String: String] = [:],
        body: (some Encodable & Sendable)? = EmptyBody?.none
    ) async throws -> Response {
        let data = try await perform(method, path, query: query, headers: headers, body: body)
        return try WireCoding.decoder.decode(Response.self, from: data)
    }

    /** 不关心响应体的请求（204 / 空 data）。 */
    public func send(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String?] = [:],
        headers: [String: String] = [:],
        body: (some Encodable & Sendable)? = EmptyBody?.none
    ) async throws {
        _ = try await perform(method, path, query: query, headers: headers, body: body)
    }

    /** 把原始字节 PUT 到绝对地址（预签名上传）；返回 HTTP 状态码，由调用方判断。 */
    public func upload(_ data: Data, to url: URL, contentType: String) async throws -> Int {
        let response = await session
            .upload(data, to: url, method: .put, headers: ["Content-Type": contentType])
            .serializingData(emptyResponseCodes: [200, 201, 204])
            .response
        if let underlying = response.error?.underlyingError, response.response == nil {
            throw underlying
        }
        return response.response?.statusCode ?? 0
    }

    private func perform(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String?],
        headers: [String: String],
        body: (some Encodable & Sendable)?
    ) async throws -> Data {
        let url = try makeURL(path, query: query)
        let httpHeaders = HTTPHeaders(headers)
        let request: DataRequest = if let body {
            session.request(
                url,
                method: method,
                parameters: body,
                encoder: JSONParameterEncoder(encoder: WireCoding.encoder),
                headers: httpHeaders
            )
        } else {
            session.request(url, method: method, headers: httpHeaders)
        }
        // validate() 让非 2xx 成为失败，401 才会进 [ProtectedRequestInterceptor.retry]。
        let response = await request
            .validate()
            .serializingData(emptyResponseCodes: [200, 201, 204, 205], emptyRequestMethods: [.head])
            .response
        let status = response.response?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let underlying = response.error?.underlyingError, response.response == nil {
                throw underlying
            }
            throw APIError(status: status, body: response.data)
        }
        return response.data ?? Data()
    }

    /** Retrofit @Query 语义：nil 参数不出现在 URL 里。 */
    private func makeURL(_ path: String, query: [String: String?]) throws -> URL {
        let url = baseURL.appendingPathComponent(path)
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        guard !items.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = items.sorted { $0.name < $1.name }
        guard let composed = components.url else { throw URLError(.badURL) }
        return composed
    }
}

/** Debug 构建打印请求与响应体（对应 OkHttp `HttpLoggingInterceptor.Level.BODY`）。 */
struct HTTPLogMonitor: EventMonitor {
    func request<Value>(_ request: DataRequest, didParseResponse response: Alamofire.DataResponse<Value, AFError>) {
        let status = response.response?.statusCode ?? 0
        let body = response.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        print("[HTTP] \(request.request?.httpMethod ?? "") \(request.request?.url?.absoluteString ?? "") → \(status)\n\(body)")
    }
}
