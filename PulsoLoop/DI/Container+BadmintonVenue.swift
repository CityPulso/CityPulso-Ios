import Factory
import PulsoLinkCore

/** 球馆羽毛球入口的依赖（Android `VenueQueryStore` / `VenueService` 里羽毛球那几项）。 */
extension Container {
    var badmintonVenueQueryStore: Factory<BadmintonVenueQueryStore> {
        self {
            let store = BadmintonVenueQueryStore(api: BadmintonEntryAPI(client: self.protectedClient()), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var badmintonVenueService: Factory<BadmintonVenueService> {
        self {
            BadmintonVenueService(
                api: BadmintonEntryAPI(client: self.protectedClient()),
                query: self.badmintonVenueQueryStore(),
                eventBus: self.venueEventBus(),
                session: self.authSessionStore()
            )
        }.singleton
    }
}
