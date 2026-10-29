import Foundation
import Testing
@testable import PulsoLinkCore

private final class RefreshCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private func makeManager(
    store: AuthSessionStore,
    bus: AuthEventBus = AuthEventBus(),
    call: @escaping TokenRefreshManager.RefreshCall
) -> TokenRefreshManager {
    TokenRefreshManager(
        refreshCall: call,
        sessionStore: store,
        deviceIdProvider: DeviceIdProvider(defaults: UserDefaults(suiteName: "tests-\(UUID().uuidString)")!),
        sessionTerminator: SessionTerminator(sessionStore: store, authEventBus: bus)
    )
}

struct TokenRefreshManagerTests {
    @Test func concurrentCallersShareOneRefresh() async throws {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let counter = RefreshCounter()
        let manager = makeManager(store: store) { request in
            counter.increment()
            #expect(request.refreshToken == "refresh-1")
            try await Task.sleep(for: .milliseconds(50))
            return TokensResponse(accessToken: "access-2", refreshToken: "refresh-2")
        }

        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<5 { group.addTask { try await manager.refresh(.unauthorized) } }
            return try await group.reduce(into: [Bool]()) { $0.append($1) }
        }

        #expect(results == Array(repeating: true, count: 5))
        #expect(counter.count == 1)
        #expect(store.state.value.accessToken == "access-2")
    }

    @Test func hardFailureEndsSession() async {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let manager = makeManager(store: store) { _ in
            throw APIError(status: 401, errCode: ErrorCodes.invalidRefreshToken)
        }

        await #expect(throws: APIError.self) { try await manager.refresh(.unauthorized) }
        #expect(store.state.value == .loggedOut)
    }

    @Test func networkFailureKeepsSession() async {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let manager = makeManager(store: store) { _ in throw URLError(.timedOut) }

        await #expect(throws: URLError.self) { try await manager.refresh(.proactive) }
        #expect(store.state.value == completeSession())
    }

    @Test func rejectedOrMissingTokenDoesNotCall() async throws {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        let counter = RefreshCounter()
        let manager = makeManager(store: store) { _ in
            counter.increment()
            return TokensResponse(accessToken: "a", refreshToken: "r")
        }

        #expect(try await manager.refresh(.unauthorized) == false)
        store.state.set(completeSession())
        store.markRejectedRefreshToken("refresh-1")
        #expect(try await manager.refresh(.unauthorized) == false)
        #expect(counter.count == 0)
    }

    @Test func proactiveBuffer() {
        let issued = Date(timeIntervalSince1970: 0)
        #expect(TokenRefreshManager.refreshBuffer(expiresAt: issued.addingTimeInterval(900), issuedAt: issued) == 90)
        // 30 天寿命 → 10% = 3 天 > 1h，不安排主动刷新
        #expect(TokenRefreshManager.refreshBuffer(expiresAt: issued.addingTimeInterval(30 * 86_400), issuedAt: issued) == nil)
        #expect(TokenRefreshManager.refreshBuffer(expiresAt: issued, issuedAt: nil) == nil)
        #expect(TokenRefreshManager.refreshBuffer(expiresAt: issued, issuedAt: issued) == nil)
    }
}
