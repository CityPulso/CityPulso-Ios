import Factory
import PulsoLinkCore

/** 门店密室逃脱入口的依赖（Android `VenueQueryStore` / `VenueService` 里密室逃脱那几项）。 */
extension Container {
    var escapeRoomVenueQueryStore: Factory<EscapeRoomVenueQueryStore> {
        self {
            let store = EscapeRoomVenueQueryStore(api: EscapeRoomEntryAPI(client: self.protectedClient()), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var escapeRoomVenueService: Factory<EscapeRoomVenueService> {
        self {
            EscapeRoomVenueService(
                api: EscapeRoomEntryAPI(client: self.protectedClient()),
                query: self.escapeRoomVenueQueryStore(),
                eventBus: self.venueEventBus(),
                session: self.authSessionStore()
            )
        }.singleton
    }
}
