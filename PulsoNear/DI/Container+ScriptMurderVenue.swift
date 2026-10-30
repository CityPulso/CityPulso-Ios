import Factory
import PulsoLinkCore

/** 门店剧本杀入口的依赖（Android `VenueQueryStore` / `VenueService` 里剧本杀那几项）。 */
extension Container {
    var scriptMurderVenueQueryStore: Factory<ScriptMurderVenueQueryStore> {
        self {
            let store = ScriptMurderVenueQueryStore(api: ScriptMurderEntryAPI(client: self.protectedClient()), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var scriptMurderVenueService: Factory<ScriptMurderVenueService> {
        self {
            ScriptMurderVenueService(
                api: ScriptMurderEntryAPI(client: self.protectedClient()),
                query: self.scriptMurderVenueQueryStore(),
                eventBus: self.venueEventBus(),
                session: self.authSessionStore()
            )
        }.singleton
    }
}
