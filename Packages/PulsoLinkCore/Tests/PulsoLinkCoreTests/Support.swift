import Foundation
@testable import PulsoLinkCore

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
