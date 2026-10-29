import Foundation
import Testing
@testable import PulsoLinkCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** 进程内假服务器：按请求返回 (status, body)，并记录收到的请求。 */
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var received: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.received.append(request) }
        let (status, body) = Self.handler?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [
            "Content-Type": "application/json",
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let config = PulsoCoreConfig(
    apiBaseURL: URL(string: "http://stub.local/api")!,
    signupPlatform: .pulsoloop,
    appName: "Test",
    shellDestinations: []
)

private func stubConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return configuration
}

/** URLProtocol 的 handler 是全局的，这组测试串行跑。 */
@Suite(.serialized)
struct APIClientTests {
    init() {
        StubProtocol.lock.withLock { StubProtocol.received = [] }
    }

    @Test func omitsNilQueryAndEncodesSnakeCase() async throws {
        StubProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://stub.local/api/auth/me/profiles?limit=20")
            return (200, #"{"data":{"items":[{"profile_id":"p1","kind":"community"}],"total":1}}"#)
        }
        let client = APIClient(config: config, interceptor: nil, configuration: stubConfiguration())
        let page: DataResponse<ListWithTotal<ProfileItem>> = try await client.request(
            .get, "auth/me/profiles", query: ["limit": "20", "offset": nil]
        )
        #expect(try page.dataOrThrow("ListProfiles").items.map(\.profileId) == ["p1"])
    }

    @Test func non2xxThrowsAPIError() async {
        StubProtocol.handler = { _ in (409, #"{"err_code":"EMAIL_TAKEN","message":"Email already used"}"#) }
        let client = APIClient(config: config, interceptor: nil, configuration: stubConfiguration())
        await #expect(throws: APIError(status: 409, errCode: "EMAIL_TAKEN", message: "Email already used")) {
            try await client.send(.post, "auth/me/emails", body: CreateEmailRequest(email: "a@b.c"))
        }
    }

    @Test func unauthorizedRefreshesOnceAndReplays() async throws {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let terminator = SessionTerminator(sessionStore: store, authEventBus: AuthEventBus())
        let refresh = TokenRefreshManager(
            refreshCall: { _ in TokensResponse(accessToken: "access-2", refreshToken: "refresh-2") },
            sessionStore: store,
            deviceIdProvider: DeviceIdProvider(defaults: UserDefaults(suiteName: "tests-\(UUID().uuidString)")!),
            sessionTerminator: terminator
        )
        StubProtocol.handler = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                ? (200, #"{"data":{"email_id":"e1"}}"#)
                : (401, #"{"err_code":"INVALID_TOKEN"}"#)
        }
        let client = APIClient(
            config: config,
            interceptor: ProtectedRequestInterceptor(sessionStore: store, tokenRefreshManager: refresh, sessionTerminator: terminator),
            configuration: stubConfiguration()
        )

        let created = try await AuthProtectedAPI(client: client).createEmail(CreateEmailRequest(email: "a@b.c"))

        #expect(try created.dataOrThrow("CreateEmail").emailId == "e1")
        let headers = StubProtocol.lock.withLock { StubProtocol.received.map { $0.value(forHTTPHeaderField: "Authorization") } }
        #expect(headers == ["Bearer access-1", "Bearer access-2"])
        #expect(store.state.value.accessToken == "access-2")
    }

    @Test func secondUnauthorizedSignsOut() async throws {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let terminator = SessionTerminator(sessionStore: store, authEventBus: AuthEventBus())
        let refresh = TokenRefreshManager(
            refreshCall: { _ in TokensResponse(accessToken: "access-2", refreshToken: "refresh-2") },
            sessionStore: store,
            deviceIdProvider: DeviceIdProvider(defaults: UserDefaults(suiteName: "tests-\(UUID().uuidString)")!),
            sessionTerminator: terminator
        )
        StubProtocol.handler = { _ in (401, #"{"err_code":"INVALID_TOKEN"}"#) }
        let client = APIClient(
            config: config,
            interceptor: ProtectedRequestInterceptor(sessionStore: store, tokenRefreshManager: refresh, sessionTerminator: terminator),
            configuration: stubConfiguration()
        )

        await #expect(throws: APIError.self) {
            try await AuthProtectedAPI(client: client).deleteEmail(emailId: "e1")
        }
        try await waitUntil { store.state.value == .loggedOut }
    }
}
