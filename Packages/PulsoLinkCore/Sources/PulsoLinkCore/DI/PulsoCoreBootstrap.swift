import Factory
import Foundation

/**
 * 宿主 App 启动入口（对应 Android `Application.onCreate` 里的那串 start()）：
 * 注册配置与会话存储 → 恢复会话 → 随会话状态调度主动刷新。
 */
public enum PulsoCoreBootstrap {
    public static func start(config: PulsoCoreConfig, vault: any SessionVault) {
        let container = Container.shared
        container.pulsoCoreConfig.register { config }
        container.sessionVault.register { vault }
        let gate = container.startupGate()
        let refresh = container.tokenRefreshManager()
        Task {
            await gate.start()
            await refresh.start()
        }
    }
}
