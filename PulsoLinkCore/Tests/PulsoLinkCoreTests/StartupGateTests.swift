import Foundation
import Testing
@testable import PulsoLinkCore

private let host = "startup-gate.stub"

/** 共用一个假主机，串行跑。 */
@Suite(.serialized)
struct StartupGateTests {
    private struct Harness {
        let gate: StartupGate
        let store: AuthSessionStore
        let profiles: ProfileStore
        let profileBootstrap: ProfileBootstrap
        let preferences: PreferenceRepository
    }

    init() {
        StubProtocol.reset(host)
    }

    private func harness(restoring session: AuthSession?) -> Harness {
        let vault = MemoryVault()
        if let session { AuthSessionPersistence(vault: vault).persist(session) }
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: vault))
        let events = AuthEventBus()
        let terminator = SessionTerminator(sessionStore: store, authEventBus: events)
        let config = stubConfig(host: host, shellDestinations: Set(ShellDestination.allCases))
        // 预热只走受保护接口；测试里不经刷新拦截器，直接带 Bearer 也不需要
        let client = APIClient(config: config, interceptor: nil, configuration: StubProtocol.configuration)
        let auth = AuthRepository(publicAPI: AuthPublicAPI(client: client), protectedAPI: AuthProtectedAPI(client: client))
        let authService = AuthService(
            auth: auth,
            authEventBus: events,
            sessionStore: store,
            profileCards: ProfileCardRepository(auth: auth, database: try! .inMemory())
        )
        let profiles = ProfileStore()
        let preferences = PreferenceRepository(defaults: freshDefaults())
        let profileBootstrap = ProfileBootstrap(authService: authService, sessionStore: store, profileStore: profiles, authEventBus: events)
        let gate = StartupGate(
            sessionStore: store,
            sessionTerminator: terminator,
            profileBootstrap: profileBootstrap,
            profileStore: profiles,
            preferenceBootstrap: PreferenceBootstrap(profileStore: profiles, preferenceRepository: preferences, config: config)
        )
        return Harness(gate: gate, store: store, profiles: profiles, profileBootstrap: profileBootstrap, preferences: preferences)
    }

    @Test func warmsUpProfileAndServerPreferenceBeforeReady() async {
        StubProtocol.serve(host) { request in
            #expect(request.url?.path == "/api/auth/me/full-account-information-with-community-profile")
            return (200, communityAccountJSON(preference: #"{"theme":{"accent":"blue"}}"#))
        }
        let h = harness(restoring: completeSession())

        await h.gate.start()

        #expect(h.gate.isReady.value)
        #expect(h.store.state.value == completeSession())
        #expect(h.profiles.current.value?.profileId == "prof-1")
        #expect(h.preferences.preference.value.theme.accent == .blue)
    }

    @Test func profileFailureStillOpensTheApp() async {
        StubProtocol.serve(host) { _ in (503, "") }
        let h = harness(restoring: completeSession())

        await h.gate.start()

        #expect(h.gate.isReady.value)
        #expect(h.profiles.current.value == nil)
        #expect(h.store.state.value == completeSession())
    }

    @Test func signsOutNonCommunitySession() async {
        var organization = completeSession()
        organization.currentProfileKind = .organization
        let h = harness(restoring: organization)

        await h.gate.start()

        #expect(h.gate.isReady.value)
        #expect(h.store.state.value == .loggedOut)
        #expect(StubProtocol.received(host).isEmpty)
    }

    @Test func signingOutClearsTheProfile() async throws {
        StubProtocol.serve(host) { _ in (200, communityAccountJSON()) }
        let h = harness(restoring: completeSession())
        await h.gate.start()
        h.profileBootstrap.start()
        #expect(h.profiles.current.value != nil)

        h.store.clearAuth()

        try await waitUntil { h.profiles.current.value == nil }
    }
}
