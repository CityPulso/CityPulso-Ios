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
                authService: self.authService(),
                sessionStore: self.authSessionStore(),
                deviceIdProvider: self.deviceIdProvider(),
                authEventBus: self.authEventBus(),
                profileBootstrap: self.profileBootstrap(),
                profileStore: self.profileStore(),
                preferenceBootstrap: self.preferenceBootstrap(),
                preferenceService: self.preferenceService(),
                config: self.pulsoCoreConfig()
            )
        }.singleton
    }

    public var authService: Factory<AuthService> {
        self { AuthService(auth: self.authRepository(), authEventBus: self.authEventBus(), sessionStore: self.authSessionStore()) }.singleton
    }

    public var authQueryStore: Factory<AuthQueryStore> {
        self {
            let store = AuthQueryStore(auth: self.authRepository(), authEventBus: self.authEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    public var startupGate: Factory<StartupGate> {
        self {
            StartupGate(
                sessionStore: self.authSessionStore(),
                sessionTerminator: self.sessionTerminator(),
                profileBootstrap: self.profileBootstrap(),
                profileStore: self.profileStore(),
                preferenceBootstrap: self.preferenceBootstrap()
            )
        }.singleton
    }

    /* ------------------------------ Asset ------------------------------ */

    public var assetRepository: Factory<AssetRepository> {
        self { AssetRepository(api: AssetAPI(client: self.protectedClient()), storage: self.publicClient()) }.singleton
    }

    /* ------------------------------ Building ------------------------------ */

    public var buildingRepository: Factory<BuildingRepository> {
        self { BuildingRepository(api: BuildingAPI(client: self.publicClient()), favorites: FavoriteAPI(client: self.protectedClient())) }.singleton
    }

    public var buildingService: Factory<BuildingService> {
        self { BuildingService(buildings: self.buildingRepository()) }.singleton
    }

    public var locationService: Factory<LocationService> {
        self { LocationService(location: LocationRepository(api: LocationAPI(client: self.protectedClient()))) }.singleton
    }

    /* ------------------------------ Payments ------------------------------ */

    public var paymentsEventBus: Factory<PaymentsEventBus> {
        self { PaymentsEventBus() }.singleton
    }

    public var paymentsService: Factory<PaymentsService> {
        self {
            let service = PaymentsService(
                api: PaymentsAPI(client: self.protectedClient()),
                publicAPI: PaymentsPublicAPI(client: self.publicClient()),
                bus: self.paymentsEventBus(),
                location: self.locationService()
            )
            self.sessionTerminator().register(service)
            return service
        }.singleton
    }

    /* ------------------------------ Social ------------------------------ */

    public var socialService: Factory<SocialService> {
        self { SocialService(social: SocialRepository(api: SocialAPI(client: self.protectedClient()))) }.singleton
    }

    /* ------------------------------ Profile / preference ------------------------------ */

    public var profileStore: Factory<ProfileStore> {
        self { ProfileStore() }.singleton
    }

    public var profileBootstrap: Factory<ProfileBootstrap> {
        self {
            ProfileBootstrap(
                authService: self.authService(),
                sessionStore: self.authSessionStore(),
                profileStore: self.profileStore(),
                authEventBus: self.authEventBus()
            )
        }.singleton
    }

    public var preferenceRepository: Factory<PreferenceRepository> {
        self { PreferenceRepository() }.singleton
    }

    public var preferenceBootstrap: Factory<PreferenceBootstrap> {
        self {
            PreferenceBootstrap(
                profileStore: self.profileStore(),
                preferenceRepository: self.preferenceRepository(),
                config: self.pulsoCoreConfig()
            )
        }.singleton
    }

    public var preferenceService: Factory<PreferenceService> {
        self {
            PreferenceService(
                preferenceRepository: self.preferenceRepository(),
                authService: self.authService(),
                sessionStore: self.authSessionStore(),
                config: self.pulsoCoreConfig()
            )
        }.singleton
    }
}
