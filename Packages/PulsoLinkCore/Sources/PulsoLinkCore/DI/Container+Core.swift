import Factory
import Foundation

/**
 * core 的依赖注册（对应 Android `NetworkModule` / `DataStoreModule` 等 Hilt 模块）。
 * 宿主 App 启动时先注册 [pulsoCoreConfig] 与 [sessionVault]，其余依赖都由它们推导，全部单例。
 */
extension Container {
    /** 由宿主 App 注册；未注册直接崩，缺配置不该带病启动。 */
    public var pulsoCoreConfig: Factory<PulsoCoreConfig> {
        self { fatalError("PulsoCoreConfig must be registered by the host app") }.singleton
    }

    /** 由宿主 App 注册（iOS 上是 [KeychainSessionVault]）。 */
    public var sessionVault: Factory<any SessionVault> {
        self { fatalError("SessionVault must be registered by the host app") }.singleton
    }

    public var authSessionStore: Factory<AuthSessionStore> {
        self { AuthSessionStore(persistence: AuthSessionPersistence(vault: self.sessionVault())) }.singleton
    }

    public var authEventBus: Factory<AuthEventBus> {
        self { AuthEventBus() }.singleton
    }

    public var deviceIdProvider: Factory<DeviceIdProvider> {
        self { DeviceIdProvider() }.singleton
    }

    public var sessionTerminator: Factory<SessionTerminator> {
        self { SessionTerminator(sessionStore: self.authSessionStore(), authEventBus: self.authEventBus()) }.singleton
    }

    public var tokenRefreshManager: Factory<TokenRefreshManager> {
        self {
            let publicAPI = self.authPublicAPI()
            return TokenRefreshManager(
                refreshCall: { try await publicAPI.refreshTokens($0).dataOrThrow("RefreshTokens") },
                sessionStore: self.authSessionStore(),
                deviceIdProvider: self.deviceIdProvider(),
                sessionTerminator: self.sessionTerminator()
            )
        }.singleton
    }

    /* ------------------------------ HTTP clients ------------------------------ */

    /** 登录/注册/刷新等公开接口，无 Bearer。 */
    public var publicClient: Factory<APIClient> {
        self { APIClient(config: self.pulsoCoreConfig()) }.singleton
    }

    /** Bearer + 401 单飞刷新重放。 */
    public var protectedClient: Factory<APIClient> {
        self {
            APIClient(
                config: self.pulsoCoreConfig(),
                interceptor: ProtectedRequestInterceptor(
                    sessionStore: self.authSessionStore(),
                    tokenRefreshManager: self.tokenRefreshManager(),
                    sessionTerminator: self.sessionTerminator()
                )
            )
        }.singleton
    }

    /* ------------------------------ Auth ------------------------------ */

    public var authPublicAPI: Factory<AuthPublicAPI> {
        self { AuthPublicAPI(client: self.publicClient()) }.singleton
    }

    public var authProtectedAPI: Factory<AuthProtectedAPI> {
        self { AuthProtectedAPI(client: self.protectedClient()) }.singleton
    }

    public var authRepository: Factory<AuthRepository> {
        self { AuthRepository(publicAPI: self.authPublicAPI(), protectedAPI: self.authProtectedAPI()) }.singleton
    }

    public var communitySignIn: Factory<CommunitySignIn> {
        self {
            CommunitySignIn(
                authRepository: self.authRepository(),
                sessionStore: self.authSessionStore(),
                deviceIdProvider: self.deviceIdProvider(),
                authEventBus: self.authEventBus()
            )
        }.singleton
    }

    public var startupGate: Factory<StartupGate> {
        self { StartupGate(sessionStore: self.authSessionStore(), sessionTerminator: self.sessionTerminator()) }.singleton
    }
}
