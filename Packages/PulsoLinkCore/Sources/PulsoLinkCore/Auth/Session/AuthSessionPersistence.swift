import Foundation

/** 会话快照的落盘位置：iOS 上是 Keychain（[KeychainSessionVault]），测试里用内存实现。 */
public protocol SessionVault: Sendable {
    func load() -> Data?
    func save(_ data: Data)
    func clear()
}

/**
 * 会话持久化（对应 WEB 单个 `auth-storage` key）：
 * - 只写「完整 + rememberMe」会话；其余情况清空存储。
 * - rememberMe=false 只留内存（WEB sessionStorage 语义）。
 * - 不完整或无法解码的数据清掉，按未登录处理。
 */
public struct AuthSessionPersistence: Sendable {
    private let vault: SessionVault

    public init(vault: SessionVault) {
        self.vault = vault
    }

    func read() -> AuthSession? {
        guard let data = vault.load() else { return nil }
        guard let snapshot = try? WireCoding.decoder.decode(AuthSessionSnapshot.self, from: data),
              !snapshot.accessToken.isEmpty,
              !snapshot.refreshToken.isEmpty,
              hasSelectedProfile(snapshot.profileId)
        else {
            vault.clear()
            return nil
        }
        return AuthSession(
            isAuthValid: snapshot.isAuthValid,
            accessToken: snapshot.accessToken,
            refreshToken: snapshot.refreshToken,
            currentAccountId: snapshot.accountId,
            currentProfileId: snapshot.profileId,
            currentProfileKind: snapshot.profileKind,
            // 能落盘就说明写入时 rememberMe=true。
            rememberMe: true
        )
    }

    /** 只写完整 rememberMe 会话；否则清空（step-1 token 永不落盘）。 */
    func persist(_ session: AuthSession) {
        guard session.isCompleteSession, session.rememberMe else {
            vault.clear()
            return
        }
        let snapshot = AuthSessionSnapshot(
            isAuthValid: session.isAuthValid,
            accessToken: session.accessToken ?? "",
            refreshToken: session.refreshToken ?? "",
            accountId: session.currentAccountId,
            profileId: session.currentProfileId,
            profileKind: session.currentProfileKind
        )
        guard let data = try? WireCoding.encoder.encode(snapshot) else { return }
        vault.save(data)
    }
}
