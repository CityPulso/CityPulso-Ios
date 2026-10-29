import Foundation
import Testing
@testable import PulsoLinkCore

struct StartupGateTests {
    private func gate(restoring session: AuthSession) -> (StartupGate, AuthSessionStore) {
        let vault = MemoryVault()
        AuthSessionPersistence(vault: vault).persist(session)
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: vault))
        let terminator = SessionTerminator(sessionStore: store, authEventBus: AuthEventBus())
        return (StartupGate(sessionStore: store, sessionTerminator: terminator), store)
    }

    @Test func keepsRestoredCommunitySession() async {
        let (gate, store) = gate(restoring: completeSession())
        await gate.start()
        #expect(gate.isReady.value)
        #expect(store.state.value == completeSession())
    }

    @Test func signsOutNonCommunitySession() async {
        var organization = completeSession()
        organization.currentProfileKind = .organization
        let (gate, store) = gate(restoring: organization)
        await gate.start()
        #expect(gate.isReady.value)
        #expect(store.state.value == .loggedOut)
    }
}
