import Foundation

/**
 * 页面能交给的另一个 CityPulso App（Android `SiblingApp`）：它接的深链 scheme（`scheme://open/<path>`）和网站，
 * 网站路径和深链路径一样。
 */
public struct SiblingApp: Sendable, Hashable {
    public let scheme: String
    public let webOrigin: String

    public init(scheme: String, webOrigin: String) {
        self.scheme = scheme
        self.webOrigin = webOrigin
    }

    public func deepLink(_ path: String) -> URL? { URL(string: "\(scheme)://open\(path)") }

    public func webURL(_ path: String) -> URL? { URL(string: "\(webOrigin)\(path)") }
}

/** 深链 `scheme://open/<path>` 的路径段和查询参数；不是 [scheme] 或 host 不是 open 时 nil。 */
public struct DeepLinkPath: Sendable, Hashable {
    public let segments: [String]
    public let query: [String: String]

    public init?(_ url: URL, scheme: String) {
        guard url.scheme == scheme, url.host() == "open", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        segments = components.path.split(separator: "/").map(String.init)
        query = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }
}
