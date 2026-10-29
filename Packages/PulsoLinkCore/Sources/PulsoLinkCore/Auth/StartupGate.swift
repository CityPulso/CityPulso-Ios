import Foundation

/**
 * 冷启动开屏门闩（对应 Android `LoopStartupGate` / `NearStartupGate`）：先恢复会话再放行 UI。
 * 手机端只有社区档：旧版本落盘的组织 / 权限档会话直接登出，重新登录即进社区档。
 */
public final class StartupGate: Sendable {
    private let sessionStore: AuthSessionStore
    private let sessionTerminator: SessionTerminator

    public let isReady = StateBroadcast(false)

    public init(sessionStore: AuthSessionStore, sessionTerminator: SessionTerminator) {
        self.sessionStore = sessionStore
        self.sessionTerminator = sessionTerminator
    }

    /** App 启动时调用一次。 */
    public func start() async {
        sessionStore.restore()
        let session = sessionStore.state.value
        if session.isCompleteSession, session.currentProfileKind != .community {
            await sessionTerminator.terminate(.startupGate)
        }
        isReady.set(true)
    }
}
