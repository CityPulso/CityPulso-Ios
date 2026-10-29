import Foundation

/**
 * 冷启动开屏门闩（对应 Android `LoopStartupGate` / `NearStartupGate`）：先恢复会话；
 * 已登录则预取档案并套用服务端偏好（最多等 [warmupTimeout] 秒），再放行主界面。
 * 手机端只有社区档：旧版本落盘的组织 / 权限档会话直接登出，重新登录即进社区档。
 * 网络失败或超时不挡进页（页内自己重试）。
 */
public final class StartupGate: Sendable {
    private static let warmupTimeout: Double = 8

    private let sessionStore: AuthSessionStore
    private let sessionTerminator: SessionTerminator
    private let profileBootstrap: ProfileBootstrap
    private let profileStore: ProfileStore
    private let preferenceBootstrap: PreferenceBootstrap

    public let isReady = StateBroadcast(false)

    public init(
        sessionStore: AuthSessionStore,
        sessionTerminator: SessionTerminator,
        profileBootstrap: ProfileBootstrap,
        profileStore: ProfileStore,
        preferenceBootstrap: PreferenceBootstrap
    ) {
        self.sessionStore = sessionStore
        self.sessionTerminator = sessionTerminator
        self.profileBootstrap = profileBootstrap
        self.profileStore = profileStore
        self.preferenceBootstrap = preferenceBootstrap
    }

    /** App 启动时调用一次。 */
    public func start() async {
        sessionStore.restore()
        let session = sessionStore.state.value
        if session.isCompleteSession, session.currentProfileKind != .community {
            await sessionTerminator.terminate(.startupGate)
        } else if session.isCompleteSession {
            let profileBootstrap = profileBootstrap
            _ = await withTimeoutOrNil(seconds: Self.warmupTimeout) {
                await profileBootstrap.ensureLoaded()
            }
            if let info = profileStore.current.value {
                preferenceBootstrap.applyFromProfile(info)
            }
        }
        isReady.set(true)
    }
}
