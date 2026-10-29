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
            let client = self.protectedClient()
            let store = VenueQueryStore(
                badminton: BadmintonEntryAPI(client: client),
                tennis: TennisEntryAPI(client: client),
                pickleball: PickleballEntryAPI(client: client),
                eventBus: self.venueEventBus()
            )
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var eventCreateDraftStore: Factory<EventCreateDraftStore> {
        self {
            let store = EventCreateDraftStore()
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }
}
