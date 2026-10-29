import Foundation

/**
 * core 的宿主配置，由各产品 App（PulsoLoop / PulsoLink / PulsoNear）在启动时注册
 *（对应 Android `PulsoCoreConfig` / WEB 的 appEnv + host wiring）。
 */
public struct PulsoCoreConfig: Sendable {
    /**
     * 主 API 根地址（Info.plist 的 `PulsoApiBaseURL`，来自 xcconfig，必填无默认）。
     * 模拟器示例 `http://localhost:10101/api`；真机示例 `http://192.168.1.76:10101/api`（Traefik 在 /api 上 strip 前缀）。
     */
    public let apiBaseURL: URL
    /** 注册来源平台 wire（POST /auth/signup/with-email 的 signupPlatform） */
    public let signupPlatform: AuthSignupPlatform
    /** 应用名（日志 / UA 等展示用） */
    public let appName: String
    /** 本 App 有页面的底栏目标；别的 App 才有的目标（Loop 的课程 / 私教 / 赛事）在这里过滤掉。 */
    public let shellDestinations: Set<ShellDestination>
    /** 是否打印 HTTP 请求体日志（仅 Debug 配置开） */
    public let debugHttpLogging: Bool

    public init(
        apiBaseURL: URL,
        signupPlatform: AuthSignupPlatform,
        appName: String,
        shellDestinations: Set<ShellDestination>,
        debugHttpLogging: Bool = false
    ) {
        self.apiBaseURL = apiBaseURL
        self.signupPlatform = signupPlatform
        self.appName = appName
        self.shellDestinations = shellDestinations
        self.debugHttpLogging = debugHttpLogging
    }
}
