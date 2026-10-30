import Foundation

/** 持有账号私有数据、会话结束时必须清掉的东西（查询缓存、本地库、壁纸、收件箱标记、图片缓存…）。 */
public protocol LogoutClearable: Sendable {
    func onLogout() async throws
}

/** 会话为什么结束：写日志，也让测试断言走的是哪条路径。 */
public enum LogoutReason: Sendable {
    /** 用户点了「退出登录」。 */
    case user
    /** refresh token 被服务端拒绝（换票硬失败）。 */
    case refreshFailed
    /** 刷新并重放一次后仍然 401。 */
    case unauthorized
    /** 启动时发现本 App 用不了的会话（如非 community 身份）。 */
    case startupGate
    /** 登录第一步之后失败了：清掉做了一半的会话，下次从头来。 */
    case signInFailed
}

/**
 * 结束会话的唯一入口。
 *
 * 顺序与 WEB 一致：先在还知道账号 id 时广播 [AuthEvent.logout]，再清内存会话（镜像随之清掉 Keychain），
 * 最后逐个清 [LogoutClearable]。清理放在不随调用方取消的 Task 里，关闭中的页面不会留下半截数据。
 */
public final class SessionTerminator: @unchecked Sendable {
    private let sessionStore: AuthSessionStore
    private let authEventBus: AuthEventBus
    private let lock = NSLock()
    private var clearables: [any LogoutClearable] = []

    public init(sessionStore: AuthSessionStore, authEventBus: AuthEventBus) {
        self.sessionStore = sessionStore
        self.authEventBus = authEventBus
    }

    /** wiring 阶段由各模块登记（对应 Hilt `Set<LogoutClearable>` multibinding）。 */
    public func register(_ clearable: any LogoutClearable) {
        lock.withLock { clearables.append(clearable) }
    }

    public func terminate(_ reason: LogoutReason) async {
        let accountId = sessionStore.state.value.currentAccountId
        authEventBus.emit(.logout(accountId: accountId == emptyAccountId ? nil : accountId))
        sessionStore.clearAuth()
        let targets = lock.withLock { clearables }
        // 非结构化 Task 不继承调用方的取消。
        await Task {
            for clearable in targets {
                do {
                    try await clearable.onLogout()
                } catch {
                    print("[SessionTerminator] logout cleanup failed: \(type(of: clearable)): \(error)")
                }
            }
        }.value
    }
}
