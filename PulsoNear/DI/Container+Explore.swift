import Factory
import PulsoLinkCore
import PulsoLinkUI

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

    var placeRequestService: Factory<PlaceRequestService> {
        self { PlaceRequestService(repository: PlaceRequestRepository(api: PlaceRequestAPI(client: self.protectedClient()))) }.singleton
    }

    var exploreLayerStore: Factory<ExploreLayerStore> {
        self { ExploreLayerStore() }.singleton
    }

    var venueNearbyFilterStore: Factory<VenueNearbyFilterStore> {
        self { VenueNearbyFilterStore() }.singleton
    }

    var activityNearbyFilterStore: Factory<ActivityNearbyFilterStore> {
        self { ActivityNearbyFilterStore() }.singleton
    }

    var chatShareDraftStore: Factory<ChatShareDraftStore> {
        self { ChatShareDraftStore() }.singleton
    }

    var discussionEventBus: Factory<DiscussionEventBus> {
        self { DiscussionEventBus() }.singleton
    }

    var discussionService: Factory<DiscussionService> {
        self { DiscussionService(repository: DiscussionRepository(api: DiscussionAPI(client: self.protectedClient())), bus: self.discussionEventBus()) }.singleton
    }

    /** 设置页「清除本地数据」的各项：本地库、聊天壁纸、图片缓存、发起草稿。 */
    var localDataService: Factory<LocalDataService> {
        self {
            LocalDataService(sources: self.pulsoDatabase().localDataSources(wallpapers: self.chatWallpaperStore()) + [
                ImageCacheDataSource(),
                CreateDraftDataSource(store: self.activityCreateDraftStore()),
            ])
        }.singleton
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
