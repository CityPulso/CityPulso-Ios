import Factory
import PulsoLinkCore

/** 门店的依赖（Android Near Hilt 里 venue 的 API / 仓储 / 缓存 / 门面）。 */
extension Container {
    var venueQueryStore: Factory<VenueQueryStore> {
        self {
            let store = VenueQueryStore(repository: self.venueRepository(), boardGames: BoardGameEntryAPI(client: self.protectedClient()), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var venueRepository: Factory<VenueRepository> {
        self { VenueRepository(publicAPI: VenuePublicAPI(client: self.publicClient()), api: VenueAPI(client: self.protectedClient())) }.singleton
    }

    var membershipQueryStore: Factory<MembershipQueryStore> {
        self {
            let store = MembershipQueryStore(memberships: MembershipRepository(api: MembershipAPI(client: self.protectedClient())), eventBus: self.venueEventBus())
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

    var favoriteService: Factory<FavoriteService> {
        self { FavoriteService(buildings: self.buildingRepository(), venues: self.venueRepository()) }.singleton
    }

    var venueService: Factory<VenueService> {
        self { VenueService(repository: self.venueRepository(), query: self.venueQueryStore(), eventBus: self.venueEventBus(), session: self.authSessionStore()) }.singleton
    }

    /** 按场次订的门店类型（密室、剧本杀）。 */
    var sessionVenueServices: Factory<[VenueActivityType: any SessionVenueService]> {
        self { [.escapeRoom: self.escapeRoomVenueService(), .scriptMurder: self.scriptMurderVenueService()] }.singleton
    }

    /** 每种门店类型的「我的预约」读写（活动中心、日程）。 */
    var venueBookingServices: Factory<[VenueActivityType: any VenueBookingService]> {
        self {
            var services: [VenueActivityType: any VenueBookingService] = [:]
            for (type, service) in self.venueActivityTypeServices() { services[type] = service }
            for (type, service) in self.sessionVenueServices() { services[type] = service }
            return services
        }.singleton
    }

    /** 按桌台 / 包间 / 机位订的门店类型各自的预约读写（密室、剧本杀按场次订，见 [sessionVenueServices]）。 */
    var venueActivityTypeServices: Factory<[VenueActivityType: any VenueActivityTypeService]> {
        self {
            [
                .boardGame: self.boardGameVenueService(),
                .mahjong: self.mahjongVenueService(),
                .ktv: self.ktvVenueService(),
                .billiards: self.billiardsVenueService(),
                .esports: self.esportsVenueService(),
            ]
        }.singleton
    }
}
