import Factory
import PulsoLinkCore

/** 门店的依赖（Android Near Hilt 里 venue 的 API / 仓储 / 缓存 / 门面）。 */
extension Container {
    var venueQueryStore: Factory<VenueQueryStore> {
        self {
            let store = VenueQueryStore(repository: self.venueRepository(), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var venueRepository: Factory<VenueRepository> {
        self { VenueRepository(publicAPI: VenuePublicAPI(client: self.publicClient()), api: VenueAPI(client: self.protectedClient())) }.singleton
    }

    var venueService: Factory<VenueService> {
        self { VenueService(repository: self.venueRepository(), query: self.venueQueryStore(), eventBus: self.venueEventBus(), session: self.authSessionStore()) }.singleton
    }
}
