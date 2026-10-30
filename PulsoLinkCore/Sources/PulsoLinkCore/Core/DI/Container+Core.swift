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
                preferenceBootstrap: self.preferenceBootstrap(),
                preferenceService: self.preferenceService(),
                sessionTerminator: self.sessionTerminator(),
                config: self.pulsoCoreConfig()
            )
        }.singleton
    }

    public var authService: Factory<AuthService> {
        self {
            AuthService(
                auth: self.authRepository(),
                authEventBus: self.authEventBus(),
                sessionStore: self.authSessionStore(),
                profileCards: ProfileCardRepository(auth: self.authRepository(), database: self.pulsoDatabase())
            )
        }.singleton
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

    /** 本地库（Android `PulsoLinkDatabase`）；登出时清空。打不开就起不来。 */
    public var pulsoDatabase: Factory<PulsoDatabase> {
        self {
            let database = try! PulsoDatabase(name: "pulsolink")
            self.sessionTerminator().register(LocalDatabaseClearable(database: database))
            return database
        }.singleton
    }

    public var socialEventBus: Factory<SocialEventBus> {
        self { SocialEventBus() }.singleton
    }

    public var socialRepository: Factory<SocialRepository> {
        self { SocialRepository(api: SocialAPI(client: self.protectedClient())) }.singleton
    }

    public var socialLocalStore: Factory<SocialLocalStore> {
        self { SocialLocalStore(database: self.pulsoDatabase()) }.singleton
    }

    public var socialQueryStore: Factory<SocialQueryStore> {
        self {
            let store = SocialQueryStore(social: self.socialRepository(), local: self.socialLocalStore(), bus: self.socialEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    public var socialService: Factory<SocialService> {
        self {
            SocialService(
                social: self.socialRepository(),
                query: self.socialQueryStore(),
                bus: self.socialEventBus(),
                local: self.socialLocalStore(),
                sessionStore: self.authSessionStore(),
                inbox: self.inboxIndicatorStore()
            )
        }.singleton
    }

    /* ------------------------------ Communication ------------------------------ */

    public var communicationEventBus: Factory<CommunicationEventBus> {
        self { CommunicationEventBus() }.singleton
    }

    public var communicationRepository: Factory<CommunicationRepository> {
        self {
            CommunicationRepository(api: CommunicationAPI(client: self.protectedClient()), realtimeAPI: RealtimeAPI(client: self.protectedClient()))
        }.singleton
    }

    public var communicationLocalStore: Factory<CommunicationLocalStore> {
        self { CommunicationLocalStore(database: self.pulsoDatabase()) }.singleton
    }

    public var communicationQueryStore: Factory<CommunicationQueryStore> {
        self {
            let store = CommunicationQueryStore(communication: self.communicationRepository(), local: self.communicationLocalStore(), bus: self.communicationEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    public var inboxIndicatorStore: Factory<InboxIndicatorStore> {
        self {
            let store = InboxIndicatorStore(sessionStore: self.authSessionStore(), communicationQuery: self.communicationQueryStore(), socialQuery: self.socialQueryStore())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    public var realtimeEventBus: Factory<RealtimeEventBus> {
        self { RealtimeEventBus() }.singleton
    }

    public var realtimePublicationDispatcher: Factory<RealtimePublicationDispatcher> {
        self {
            RealtimePublicationDispatcher(communicationBus: self.communicationEventBus(), socialBus: self.socialEventBus(), inbox: self.inboxIndicatorStore())
        }.singleton
    }

    /** App 启动时 `start()` 一次（Android `PulsoLoopApplication.onCreate`）。 */
    public var realtimeConnectionManager: Factory<RealtimeConnectionManager> {
        self {
            RealtimeConnectionManager(
                communication: self.communicationRepository(),
                sessionStore: self.authSessionStore(),
                dispatcher: self.realtimePublicationDispatcher(),
                realtimeBus: self.realtimeEventBus(),
                communicationBus: self.communicationEventBus(),
                socialBus: self.socialEventBus(),
                inbox: self.inboxIndicatorStore()
            )
        }.singleton
    }

    public var chatLocalRepository: Factory<ChatLocalRepository> {
        self { ChatLocalRepository(database: self.pulsoDatabase(), sessionStore: self.authSessionStore()) }.singleton
    }

    public var chatWallpaperStore: Factory<ChatWallpaperStore> {
        self {
            let store = ChatWallpaperStore()
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    public var communicationService: Factory<CommunicationService> {
        self {
            CommunicationService(
                communication: self.communicationRepository(),
                query: self.communicationQueryStore(),
                bus: self.communicationEventBus(),
                inbox: self.inboxIndicatorStore(),
                local: self.communicationLocalStore()
            )
        }.singleton
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
