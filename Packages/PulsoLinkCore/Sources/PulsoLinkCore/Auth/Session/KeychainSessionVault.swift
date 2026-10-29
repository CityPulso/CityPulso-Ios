#if os(iOS) || os(macOS)
import Foundation
import KeychainAccess

/** Keychain 里的会话快照：仅本机、首次解锁后可读（后台刷新 token 时也能取到）。 */
public struct KeychainSessionVault: SessionVault {
    private static let key = "auth-session"
    private let keychain: Keychain

    public init(service: String) {
        keychain = Keychain(service: service).accessibility(.afterFirstUnlockThisDeviceOnly)
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
