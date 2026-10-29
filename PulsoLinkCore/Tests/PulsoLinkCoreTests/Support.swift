import Foundation
@testable import PulsoLinkCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** 内存 Keychain 替身。 */
final class MemoryVault: SessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    init(_ data: Data? = nil) {
        stored = data
    }

    var data: Data? { lock.withLock { stored } }

    func load() -> Data? { lock.withLock { stored } }
    func save(_ data: Data) { lock.withLock { stored = data } }
    func clear() { lock.withLock { stored = nil } }
}

func completeSession(rememberMe: Bool = true) -> AuthSession {
    AuthSession(
        isAuthValid: true,
        accessToken: "access-1",
        refreshToken: "refresh-1",
        currentAccountId: "acc-1",
        currentProfileId: "prof-1",
        currentProfileKind: .community,
        rememberMe: rememberMe
    )
}

func decodeWire<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try WireCoding.decoder.decode(type, from: Data(json.utf8))
}

/**
 * 进程内假服务器：每个测试套件用自己的主机名注册 handler，并行跑的套件互不干扰。
 * handler 按请求返回 (status, body)；收到的请求按主机记录。
 */
final class StubProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (Int, String)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return configuration
    }

    static func serve(_ host: String, _ handler: @escaping Handler) {
        lock.withLock { handlers[host] = handler }
    }

    static func reset(_ host: String) {
        lock.withLock {
            handlers[host] = nil
            requests[host] = []
        }
    }

    static func received(_ host: String) -> [URLRequest] {
        lock.withLock { requests[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let handler = Self.lock.withLock {
            Self.requests[host, default: []].append(request)
            return Self.handlers[host]
        }
        let (status, body) = handler?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [
            "Content-Type": "application/json",
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func stubConfig(host: String, shellDestinations: Set<ShellDestination> = []) -> PulsoCoreConfig {
    PulsoCoreConfig(
        apiBaseURL: URL(string: "http://\(host)/api")!,
        signupPlatform: .pulsoloop,
        appName: "Test",
        shellDestinations: shellDestinations
    )
}

func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
}

/** GET full-account-information-with-community-profile 的响应体（profile.preference 是服务端存的 camelCase）。 */
func communityAccountJSON(preference: String? = nil) -> String {
    let preferenceField = preference.map { #","preference":\#($0)"# } ?? ""
    return #"""
    {"data":{"account":{"id":"acc-1","account_status":"active","signup_platform":"pulsoloop",
    "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"},
    "community_profile":{"profile_id":"prof-1","account_id":"acc-1","citypulso_id":"prof-1","profile_language":"zh",
    "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","community_roles":["pulser"]\#(preferenceField)}}}
    """#
}
