import Foundation
import Alamofire
import Testing
@testable import PulsoLinkCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct UiErrorTests {
    @Test func categoriesFollowStatusAndTransport() {
        #expect(UiError(APIError(status: 404)).kind == .notFound)
        #expect(UiError(APIError(status: 403)).kind == .unauthorized)
        #expect(UiError(APIError(status: 504)).kind == .timeout)
        #expect(UiError(APIError(status: 502)).kind == .server)
        #expect(UiError(APIError(status: 0)).kind == .offline)
        #expect(UiError(URLError(.notConnectedToInternet)).kind == .offline)
        #expect(UiError(URLError(.timedOut)).kind == .timeout)
        #expect(UiError(MissingCommunityProfileError()).kind == .unknown)
    }

    @Test func onlyBackendBusinessMessagesReachTheScreen() {
        let error = UiError(APIError(status: 409, errCode: "EMAIL_TAKEN", message: "Email already used"))
        #expect(error.message == "Email already used")
        #expect(error.errCode == "EMAIL_TAKEN")
        #expect(UiError(APIError(status: 502, body: Data("<html>Bad Gateway</html>".utf8))).message == nil)
    }
}

private let host = "sign-in.stub"

/** 共用一个假主机，串行跑。 */
@Suite(.serialized)
struct CommunitySignInTests {
    init() {
        StubProtocol.reset(host)
    }

    private struct Harness {
        let signIn: CommunitySignIn
        let store: AuthSessionStore
        let profiles: ProfileStore
        let preferences: PreferenceRepository
    }

    private func harness() -> Harness {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.restore()
        let events = AuthEventBus()
        let config = stubConfig(host: host, shellDestinations: Set(ShellDestination.allCases))
        let client = APIClient(config: config, interceptor: BearerOnly(store: store), configuration: StubProtocol.configuration)
        let authService = AuthService(
            auth: AuthRepository(publicAPI: AuthPublicAPI(client: client), protectedAPI: AuthProtectedAPI(client: client)),
            authEventBus: events
        )
        let profiles = ProfileStore()
        let preferences = PreferenceRepository(defaults: freshDefaults())
        let profileBootstrap = ProfileBootstrap(authService: authService, sessionStore: store, profileStore: profiles, authEventBus: events)
        let signIn = CommunitySignIn(
            authService: authService,
            sessionStore: store,
            deviceIdProvider: DeviceIdProvider(defaults: freshDefaults()),
            authEventBus: events,
            profileBootstrap: profileBootstrap,
            profileStore: profiles,
            preferenceBootstrap: PreferenceBootstrap(profileStore: profiles, preferenceRepository: preferences, config: config),
            preferenceService: PreferenceService(
                preferenceRepository: preferences,
                authService: authService,
                sessionStore: store,
                config: config
            ),
            config: config
        )
        return Harness(signIn: signIn, store: store, profiles: profiles, preferences: preferences)
    }

    @Test func emailLoginSelectsCommunityProfileAndAppliesServerPreference() async throws {
        StubProtocol.serve(host) { request in
            switch request.url?.path {
            case "/api/auth/login/with-email":
                return (200, #"""
                {"data":{"account_id":"acc-1","access_token":"step1","refresh_token":"step1-r",
                 "profiles":[{"profile_id":"org-1","kind":"organization"},{"profile_id":"prof-1","kind":"community"}]}}
                """#)
            case "/api/auth/me/select-profile":
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer step1")
                return (200, #"{"data":{"account_id":"acc-1","profile_id":"prof-1","access_token":"full","refresh_token":"full-r"}}"#)
            case "/api/auth/me/full-account-information-with-community-profile":
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer full")
                return (200, communityAccountJSON(preference: #"{"theme":{"accent":"grass"}}"#))
            default:
                return (404, "")
            }
        }
        let h = harness()

        try await h.signIn.loginWithEmail(email: "a@b.c", password: "secret12", rememberMe: true)

        let session = h.store.state.value
        #expect(session.isCompleteSession)
        #expect(session.currentProfileId == "prof-1")
        #expect(session.currentProfileKind == .community)
        #expect(session.rememberMe)
        #expect(h.profiles.current.value?.profileId == "prof-1")
        #expect(h.preferences.preference.value.theme.accent == .grass)
    }

    @Test func accountWithoutCommunityProfileIsRejected() async {
        StubProtocol.serve(host) { _ in
            (200, #"{"data":{"account_id":"acc-1","access_token":"a","refresh_token":"r","profiles":[{"profile_id":"o","kind":"organization"}]}}"#)
        }
        let h = harness()
        await #expect(throws: MissingCommunityProfileError.self) {
            try await h.signIn.loginWithEmail(email: "a@b.c", password: "secret12", rememberMe: false)
        }
        #expect(!h.store.state.value.hasSelectedProfile)
    }
}

/** 只加 Bearer、不刷新的拦截器（这组测试不测 401）。 */
private struct BearerOnly: RequestInterceptor {
    let store: AuthSessionStore

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, any Error>) -> Void) {
        var request = urlRequest
        if let token = store.state.value.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        completion(.success(request))
    }
}
