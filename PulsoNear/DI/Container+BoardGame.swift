import Factory
import PulsoLinkCore

/** 桌游的依赖（对应 Android Hilt 里 boardGame 的 API / 仓储 / 缓存 / 门面）。 */
extension Container {
    var boardGameEventBus: Factory<BoardGameEventBus> {
        self { BoardGameEventBus() }.singleton
    }

    var boardGameRepository: Factory<BoardGameRepository> {
        self {
            BoardGameRepository(
                publicAPI: BoardGamePublicAPI(client: self.publicClient()),
                protectedAPI: BoardGameProtectedAPI(client: self.protectedClient())
            )
        }.singleton
    }

    var boardGameQueryStore: Factory<BoardGameQueryStore> {
        self {
            let store = BoardGameQueryStore(repository: self.boardGameRepository(), eventBus: self.boardGameEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var boardGameService: Factory<BoardGameService> {
        self {
            BoardGameService(
                repository: self.boardGameRepository(),
                query: self.boardGameQueryStore(),
                eventBus: self.boardGameEventBus(),
                exploreQuery: self.exploreQueryStore()
            )
        }.singleton
    }
}
