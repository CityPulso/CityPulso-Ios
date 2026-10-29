import Factory
import Foundation

/**
 * 宿主 App 启动入口（对应 Android `Application.onCreate` 里的那串 start()）：
 * 注册配置与会话存储 → 恢复会话并预热档案 → 随会话状态拉档案、套偏好、调度主动刷新。
 */
public enum PulsoCoreBootstrap {
    public static func start(config: PulsoCoreConfig, vault: any SessionVault) {
        let container = Container.shared
        container.pulsoCoreConfig.register { config }
        container.sessionVault.register { vault }
        let gate = container.startupGate()
        let refresh = container.tokenRefreshManager()
        let profiles = container.profileBootstrap()
        let preferences = container.preferenceBootstrap()
        Task {
            await gate.start()
            profiles.start()
            preferences.start()
            await refresh.start()
        }
    }
}
