import Factory
import PulsoLinkCore

/** 门店桌游入口的依赖（Android `VenueQueryStore` / `VenueService` 里桌游那几项）。 */
extension Container {
    var boardGameVenueQueryStore: Factory<BoardGameVenueQueryStore> {
        self {
            let store = BoardGameVenueQueryStore(api: BoardGameEntryAPI(client: self.protectedClient()), eventBus: self.venueEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var boardGameVenueService: Factory<BoardGameVenueService> {
        self {
            BoardGameVenueService(
                api: BoardGameEntryAPI(client: self.protectedClient()),
                query: self.boardGameVenueQueryStore(),
                eventBus: self.venueEventBus(),
                session: self.authSessionStore()
            )
        }.singleton
    }
}
