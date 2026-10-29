import Factory
import PulsoLinkCore

/** 羽毛球的依赖（对应 Android Hilt 里 badminton 的 API / 仓储 / 缓存 / 门面）。 */
extension Container {
    var badmintonEventBus: Factory<BadmintonEventBus> {
        self { BadmintonEventBus() }.singleton
    }

    var badmintonRepository: Factory<BadmintonRepository> {
        self {
            BadmintonRepository(
                publicAPI: BadmintonPublicAPI(client: self.publicClient()),
                protectedAPI: BadmintonProtectedAPI(client: self.protectedClient())
            )
        }.singleton
    }

    var badmintonQueryStore: Factory<BadmintonQueryStore> {
        self {
            let store = BadmintonQueryStore(repository: self.badmintonRepository(), eventBus: self.badmintonEventBus())
            self.sessionTerminator().register(store)
            return store
        }.singleton
    }

    var badmintonService: Factory<BadmintonService> {
        self {
            BadmintonService(
                repository: self.badmintonRepository(),
                query: self.badmintonQueryStore(),
                eventBus: self.badmintonEventBus(),
                exploreQuery: self.exploreQueryStore()
            )
        }.singleton
    }
}
