import Foundation
import Testing
@testable import PulsoLinkCore

struct AuthSessionTests {
    @Test func persistsOnlyCompleteRememberedSession() {
        let vault = MemoryVault()
        let persistence = AuthSessionPersistence(vault: vault)

        persistence.persist(completeSession(rememberMe: false))
        #expect(vault.data == nil)

        var stepOne = completeSession()
        stepOne.currentProfileId = emptyProfileId
        persistence.persist(stepOne)
        #expect(vault.data == nil)

        persistence.persist(completeSession())
        #expect(persistence.read() == completeSession())
    }

    @Test func clearsUnreadableSnapshot() {
        let vault = MemoryVault(Data("not json".utf8))
        #expect(AuthSessionPersistence(vault: vault).read() == nil)
        #expect(vault.data == nil)
    }

    @Test func storeMirrorsToVaultAfterRestore() async throws {
        let vault = MemoryVault()
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: vault))
        store.restore()
        store.state.set(completeSession())
        try await waitUntil { vault.data != nil }

        let restored = AuthSessionStore(persistence: AuthSessionPersistence(vault: vault))
        restored.restore()
        #expect(restored.state.value == completeSession())
        #expect(restored.isRestored.value)
    }

    @Test func newTokensClearRejectedGate() {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.markRejectedRefreshToken("r1")
        #expect(store.isRejectedRefreshToken("r1"))
        store.setTokens(TokensResponse(accessToken: "a2", refreshToken: "r2"))
        #expect(!store.isRejectedRefreshToken("r1"))
        #expect(store.state.value.refreshToken == "r2")
    }

    @Test func terminatorBroadcastsThenClears() async {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let bus = AuthEventBus()
        let events = bus.events()
        let cleared = MemoryVault(Data("x".utf8))
        let terminator = SessionTerminator(sessionStore: store, authEventBus: bus)
        terminator.register(VaultClearable(vault: cleared))

        await terminator.terminate(.user)

        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .logout(accountId: "acc-1"))
        #expect(store.state.value == .loggedOut)
        #expect(cleared.data == nil)
    }
}

private struct VaultClearable: LogoutClearable {
    let vault: MemoryVault
    func onLogout() async throws { vault.clear() }
}

func waitUntil(_ condition: @Sendable () -> Bool) async throws {
    for _ in 0..<100 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
