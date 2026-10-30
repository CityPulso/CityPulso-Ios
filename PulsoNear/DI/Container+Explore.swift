import Factory
import PulsoLinkCore

/** 地图 / 附近搜索的依赖（Android Explore 与位置相关的单例）。 */
extension Container {
    var exploreQueryStore: Factory<ExploreQueryStore> {
        self {
            let buses = self
            let store = ExploreQueryStore(
                repository: ExploreRepository(publicAPI: ExplorePublicAPI(client: self.publicClient())),
                activityTypeInvalidations: [
                    { buses.mahjongEventBus().signals { _ in true } },
                    { buses.texasHoldemEventBus().signals { _ in true } },
                    { buses.boardGameEventBus().signals { _ in true } },
                    { buses.werewolfEventBus().signals { _ in true } },
                    { buses.scriptMurderEventBus().signals { _ in true } },
                    { buses.billiardsEventBus().signals { _ in true } },
                    { buses.escapeRoomEventBus().signals { _ in true } },
                    { buses.esportsEventBus().signals { _ in true } },
                    { buses.ktvEventBus().signals { _ in true } },
                    { buses.barPartyEventBus().signals { _ in true } },
                    { buses.indoorSocialEventBus().signals { _ in true } },
                    { buses.outdoorSocialEventBus().signals { _ in true } },
                    { buses.languageExchangeEventBus().signals { _ in true } },
                    { buses.bookClubEventBus().signals { _ in true } },
                    { buses.diyEventBus().signals { _ in true } },
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
                buses.mahjongEventBus().invalidate()
                buses.texasHoldemEventBus().invalidate()
                buses.boardGameEventBus().invalidate()
                buses.werewolfEventBus().invalidate()
                buses.scriptMurderEventBus().invalidate()
                buses.billiardsEventBus().invalidate()
                buses.escapeRoomEventBus().invalidate()
                buses.esportsEventBus().invalidate()
                buses.ktvEventBus().invalidate()
                buses.barPartyEventBus().invalidate()
                buses.indoorSocialEventBus().invalidate()
                buses.outdoorSocialEventBus().invalidate()
                buses.languageExchangeEventBus().invalidate()
                buses.bookClubEventBus().invalidate()
                buses.diyEventBus().invalidate()
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

    var deviceLocationBootstrap: Factory<DeviceLocationBootstrap> {
        self { DeviceLocationBootstrap(store: self.deviceLocationStore()) }.singleton
    }

    var activityNearbyFilterStore: Factory<ActivityNearbyFilterStore> {
        self { ActivityNearbyFilterStore() }.singleton
    }

    var activityCreateDraftStore: Factory<ActivityCreateDraftStore> {
        self {
            let store = ActivityCreateDraftStore()
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var venueEventBus: Factory<VenueEventBus> {
        self { VenueEventBus() }.singleton
    }
}
