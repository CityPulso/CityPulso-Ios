import Factory
import PulsoLinkCore

/** 地图 / 附近搜索的依赖（Android Explore 与位置相关的单例）。 */
extension Container {
    var exploreQueryStore: Factory<ExploreQueryStore> {
        self {
            let buses = self
            let store = ExploreQueryStore(
                repository: ExploreRepository(publicAPI: ExplorePublicAPI(client: self.publicClient())),
                sportInvalidations: [
                    { buses.badmintonEventBus().signals { _ in true } },
                    { buses.tennisEventBus().signals { _ in true } },
                    { buses.pickleballEventBus().signals { _ in true } },
                    { buses.basketballEventBus().signals { _ in true } },
                    { buses.footballEventBus().signals { _ in true } },
                    { buses.baseballEventBus().signals { _ in true } },
                    { buses.golfEventBus().signals { _ in true } },
                    { buses.hikingEventBus().signals { _ in true } },
                    { buses.fishingEventBus().signals { _ in true } },
                    { buses.skiEventBus().signals { _ in true } },
                    { buses.tableTennisEventBus().signals { _ in true } },
                ]
            )
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var exploreService: Factory<ExploreService> {
        self {
            let buses = self
            return ExploreService(query: self.exploreQueryStore()) {
                buses.badmintonEventBus().invalidate()
                buses.tennisEventBus().invalidate()
                buses.pickleballEventBus().invalidate()
                buses.basketballEventBus().invalidate()
                buses.footballEventBus().invalidate()
                buses.baseballEventBus().invalidate()
                buses.golfEventBus().invalidate()
                buses.hikingEventBus().invalidate()
                buses.fishingEventBus().invalidate()
                buses.skiEventBus().invalidate()
                buses.tableTennisEventBus().invalidate()
            }
        }.singleton
    }

    var deviceLocationStore: Factory<DeviceLocationStore> {
        self { DeviceLocationStore() }.singleton
    }

    var nearbyQueryLocationStore: Factory<NearbyQueryLocationStore> {
        self { NearbyQueryLocationStore(device: self.deviceLocationStore()) }.singleton
    }

    var exploreFocusStore: Factory<ExploreFocusStore> {
        self { ExploreFocusStore() }.singleton
    }

    var eventNearbyFilterStore: Factory<EventNearbyFilterStore> {
        self { EventNearbyFilterStore() }.singleton
    }

    var deviceLocationBootstrap: Factory<DeviceLocationBootstrap> {
        self { DeviceLocationBootstrap(store: self.deviceLocationStore()) }.singleton
    }
}

extension Container {
    var venueEventBus: Factory<VenueEventBus> {
        self { VenueEventBus() }.singleton
    }

    var venueQueryStore: Factory<VenueQueryStore> {
        self {
            let store = VenueQueryStore(repository: self.venueRepository(), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    /** 开了球馆入口的运动各自的订场读写。 */
    var venueSportServices: Factory<[VenueSport: any VenueSportService]> {
        self {
            [
                .badminton: self.badmintonVenueService(),
                .tennis: self.tennisVenueService(),
                .pickleball: self.pickleballVenueService(),
            ]
        }.singleton
    }

    var membershipQueryStore: Factory<MembershipQueryStore> {
        self {
            let client = self.protectedClient()
            let store = MembershipQueryStore(
                memberships: MembershipRepository(api: MembershipAPI(client: client)),
                bundles: BundleRepository(api: BundleAPI(client: client)),
                eventBus: self.venueEventBus()
            )
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var membershipService: Factory<MembershipService> {
        self {
            MembershipService(
                repository: MembershipRepository(api: MembershipAPI(client: self.protectedClient())),
                query: self.membershipQueryStore(),
                eventBus: self.venueEventBus(),
                session: self.authSessionStore()
            )
        }.singleton
    }

    var bundleService: Factory<BundleService> {
        self {
            BundleService(
                repository: BundleRepository(api: BundleAPI(client: self.protectedClient())),
                query: self.membershipQueryStore(),
                eventBus: self.venueEventBus(),
                session: self.authSessionStore()
            )
        }.singleton
    }

    var favoriteService: Factory<FavoriteService> {
        self { FavoriteService(buildings: self.buildingRepository(), venues: self.venueRepository()) }.singleton
    }

    var coachService: Factory<CoachService> {
        self { CoachService(repository: CoachRepository(api: CoachAPI(client: self.protectedClient())), eventBus: self.venueEventBus(), profileStore: self.profileStore()) }.singleton
    }

    var courseService: Factory<CourseService> {
        self { CourseService(repository: CourseRepository(api: CourseAPI(client: self.protectedClient())), eventBus: self.venueEventBus()) }.singleton
    }

    var venueRepository: Factory<VenueRepository> {
        self { VenueRepository(publicAPI: VenuePublicAPI(client: self.publicClient()), api: VenueAPI(client: self.protectedClient())) }.singleton
    }

    var venueService: Factory<VenueService> {
        self { VenueService(repository: self.venueRepository(), query: self.venueQueryStore(), eventBus: self.venueEventBus(), session: self.authSessionStore()) }.singleton
    }

    var tournamentService: Factory<TournamentService> {
        self { TournamentService(repository: TournamentRepository(api: TournamentAPI(client: self.protectedClient())), eventBus: self.venueEventBus()) }.singleton
    }

    var placeRequestService: Factory<PlaceRequestService> {
        self { PlaceRequestService(repository: PlaceRequestRepository(api: PlaceRequestAPI(client: self.protectedClient()))) }.singleton
    }

    var venueNearbyFilterStore: Factory<VenueNearbyFilterStore> {
        self { VenueNearbyFilterStore() }.singleton
    }

    var exploreLayerStore: Factory<ExploreLayerStore> {
        self { ExploreLayerStore() }.singleton
    }

    var eventCreateDraftStore: Factory<EventCreateDraftStore> {
        self {
            let store = EventCreateDraftStore()
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }
}

extension Container {
    /** 选择页（位置 / 活动 / 收藏）把要分享的内容交给聊天室。 */
    var chatShareDraftStore: Factory<ChatShareDraftStore> {
        self { ChatShareDraftStore() }.singleton
    }
}
