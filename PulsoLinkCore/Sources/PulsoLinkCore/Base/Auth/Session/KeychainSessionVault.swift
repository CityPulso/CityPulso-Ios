#if os(iOS) || os(macOS)
import Foundation
import KeychainAccess

/** Keychain 里的会话快照：仅本机、首次解锁后可读（后台刷新 token 时也能取到）。 */
public struct KeychainSessionVault: SessionVault {
    private static let key = "auth-session"
    private let service: String

    public init(service: String) {
        self.service = service
    }

    // KeychainAccess 的 `Keychain` 不是 Sendable，按调用现建（只是一组查询参数，没有连接或缓存）。
    private var keychain: Keychain {
        Keychain(service: service).accessibility(.afterFirstUnlockThisDeviceOnly)
    }

    public func load() -> Data? {
        try? keychain.getData(Self.key)
    }

    public func save(_ data: Data) {
        try? keychain.set(data, key: Self.key)
    }

    public func clear() {
        try? keychain.remove(Self.key)
    }
}
#endif
