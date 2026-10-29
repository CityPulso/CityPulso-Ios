import Foundation

/**
 * 认证会话内存真相（对应 WEB Zustand AuthStore）：
 * - 所有写入先进内存，再镜像到持久层（仅完整 rememberMe 会话）。
 * - rejected refresh token 门闩：硬失败过的 refresh token 在换票/清空前不再重试。
 */
public final class AuthSessionStore: @unchecked Sendable {
    private let persistence: AuthSessionPersistence
    private let lock = NSLock()
    private var rejectedRefreshToken: String?
    private var mirrorTask: Task<Void, Never>?

    public let state = StateBroadcast(AuthSession.loggedOut)
    /** 启动时持久化会话是否已恢复（UI 等待此标记再决定登录/主页） */
    public let isRestored = StateBroadcast(false)

    public init(persistence: AuthSessionPersistence) {
        self.persistence = persistence
    }

    /** App 启动时调用一次：恢复持久化会话，并开启「内存 → 持久层」镜像。 */
    public func restore() {
        guard !isRestored.value else { return }
        if let restored = persistence.read() { state.set(restored) }
        isRestored.set(true)
        let persistence = persistence
        let updates = state.values()
        mirrorTask = Task {
            for await session in updates { persistence.persist(session) }
        }
    }

    public func setIsAuthValid(_ isAuthValid: Bool) {
        state.update { $0.isAuthValid = isAuthValid }
    }

    /** 换票成功（登录/刷新/选档）；新 token 抹掉 rejected 门闩。 */
    public func setTokens(_ tokens: TokensResponse, rememberMe: Bool? = nil) {
        clearRejectedRefreshToken()
        state.update {
            $0.accessToken = tokens.accessToken
            $0.refreshToken = tokens.refreshToken
            if let rememberMe { $0.rememberMe = rememberMe }
        }
    }

    public func setCurrentAccountId(_ accountId: String) {
        state.update { $0.currentAccountId = accountId }
    }

    public func setCurrentProfileId(_ profileId: String) {
        state.update { $0.currentProfileId = profileId }
    }

    public func setCurrentProfileKind(_ kind: ProfileKind) {
        state.update { $0.currentProfileKind = kind }
    }

    /** step1 登录后清掉上一账号残留的 profile 选择（避免未选档却带着旧 profileId）。 */
    public func clearProfileSelection() {
        state.update {
            $0.currentProfileId = emptyProfileId
            $0.currentProfileKind = .fallback
        }
    }

    public func clearAuth() {
        clearRejectedRefreshToken()
        state.set(.loggedOut)
    }

    /* ---------------- rejected refresh gate（对应 WEB markRejectedRefreshToken） ---------------- */

    public func markRejectedRefreshToken(_ token: String) {
        lock.withLock { rejectedRefreshToken = token }
    }

    public func isRejectedRefreshToken(_ token: String) -> Bool {
        lock.withLock { rejectedRefreshToken == token }
    }

    public func clearRejectedRefreshToken() {
        lock.withLock { rejectedRefreshToken = nil }
    }
}
