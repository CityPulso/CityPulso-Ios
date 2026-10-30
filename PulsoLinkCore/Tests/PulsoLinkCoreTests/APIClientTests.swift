import Foundation
import Testing
@testable import PulsoLinkCore

private let host = "api-client.stub"
private let config = stubConfig(host: host)

/** 这组测试共用一个假主机，串行跑。 */
@Suite(.serialized, .timeLimit(.minutes(1)))
struct APIClientTests {
    init() {
        StubProtocol.reset(host)
    }

    @Test func omitsNilQueryAndEncodesSnakeCase() async throws {
        StubProtocol.serve(host) { request in
            #expect(request.url?.absoluteString == "http://\(host)/api/auth/me/profiles?limit=20")
            return (200, #"{"data":{"items":[{"profile_id":"p1","kind":"community"}],"total":1}}"#)
        }
        let client = APIClient(config: config, interceptor: nil, configuration: StubProtocol.configuration)
        let page: DataResponse<ListWithTotal<ProfileItem>> = try await client.request(
            .get, "auth/me/profiles", query: ["limit": "20", "offset": nil]
        )
        #expect(try page.dataOrThrow("ListProfiles").items.map(\.profileId) == ["p1"])
    }

    @Test func non2xxThrowsAPIError() async {
        StubProtocol.serve(host) { _ in (409, #"{"err_code":"EMAIL_TAKEN","message":"Email already used"}"#) }
        let client = APIClient(config: config, interceptor: nil, configuration: StubProtocol.configuration)
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
        StubProtocol.serve(host) { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                ? (200, #"{"data":{"email_id":"e1"}}"#)
                : (401, #"{"err_code":"INVALID_TOKEN"}"#)
        }
        let client = APIClient(
            config: config,
            interceptor: ProtectedRequestInterceptor(sessionStore: store, tokenRefreshManager: refresh, sessionTerminator: terminator),
            configuration: StubProtocol.configuration
        )

        let created = try await AuthProtectedAPI(client: client).createEmail(CreateEmailRequest(email: "a@b.c"))

        #expect(try created.dataOrThrow("CreateEmail").emailId == "e1")
        let headers = StubProtocol.received(host).map { $0.value(forHTTPHeaderField: "Authorization") }
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
        StubProtocol.serve(host) { _ in (401, #"{"err_code":"INVALID_TOKEN"}"#) }
        let client = APIClient(
            config: config,
            interceptor: ProtectedRequestInterceptor(sessionStore: store, tokenRefreshManager: refresh, sessionTerminator: terminator),
            configuration: StubProtocol.configuration
        )

        await #expect(throws: APIError.self) {
            try await AuthProtectedAPI(client: client).deleteEmail(emailId: "e1")
        }
        try await waitUntil { store.state.value == .loggedOut }
    }
}
