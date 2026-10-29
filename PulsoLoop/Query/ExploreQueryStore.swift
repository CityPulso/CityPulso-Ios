import PulsoLinkCore

struct NearbyPinsKey: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var longitude: Double
    var latitude: Double
    /** 地图视野半径；nil = 不限距离（搜索列表：全部，按远近排）。 */
    var radiusM: Int?
    var includeEnded: Bool?
    var search: String?
    var startsAtFrom: String?
    var startsAtTo: String?
    var maxPrice: Double?
    var offset = 0
    var limit = 15
    var summary = false
    /** 空 = 所有已上线的运动。 */
    var eventTypes: [LoopEventType] = []
    /** 只看还有空位的活动。 */
    var openSpotsOnly = false
    var sort: EventNearbySort = .distance
}

/**
 * 所有运动的附近活动针（对应 Android `ExploreQueryStore`、WEB `hooks/explore.ts`）：一页混合了各运动，
 * 任何一个运动有写操作都让它失效。本地加的浏览数叠在缓存上，直到下次拉取。
 */
final class ExploreQueryStore: LogoutClearable {
    let nearby: MemoryQuery<NearbyPinsKey, NearbyPinsPage>

    /** [sportInvalidations]：每个运动的失效脉冲（各运动的事件类型不同，所以传工厂）。 */
    init(repository: ExploreRepository, sportInvalidations: [@Sendable () -> AsyncStream<Void>]) {
        nearby = MemoryQuery(invalidates: {
            let streams = sportInvalidations.map { $0() }
            return AsyncStream { continuation in
                let tasks = streams.map { stream in
                    Task { for await _ in stream { continuation.yield() } }
                }
                continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
            }
        }) { key in
            try await repository.listNearbyPins(ListNearbyPinsRequest(
                near: GeoNearQuery(longitude: key.longitude, latitude: key.latitude, radiusM: key.radiusM),
                includeEnded: key.includeEnded == true ? true : nil,
                search: key.search,
                startsAtFrom: key.startsAtFrom,
                startsAtTo: key.startsAtTo,
                maxPrice: key.maxPrice,
                offset: key.offset,
                limit: key.limit,
                summary: key.summary,
                eventTypes: key.eventTypes.isEmpty ? nil : key.eventTypes,
                openSpotsOnly: key.openSpotsOnly ? true : nil,
                sort: key.sort == .distance ? nil : key.sort
            ))
        }
    }

    func overlayView(eventId: String, view: Int) async {
        guard !eventId.isEmpty, view >= 0 else { return }
        await nearby.updateAll { page in
            var page = page
            for index in page.items.indices where page.items[index].id == eventId && page.items[index].view < view {
                page.items[index].view = view
            }
            return page
        }
    }

    func onLogout() async throws {
        await nearby.clear()
    }
}
