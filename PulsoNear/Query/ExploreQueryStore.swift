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
    /** 空 = 所有已上线的活动类型。 */
    var activityTypes: [NearActivityType] = []
    /** 只看还有空位的活动。 */
    var openSpotsOnly = false
    var sort: ActivityNearbySort = .distance
}

/**
 * 所有活动类型的附近活动针（对应 Android `ExploreQueryStore`、WEB `hooks/explore.ts`）：一页混合了各活动类型，
 * 任何一个活动类型有写操作都让它失效。本地加的浏览数叠在缓存上，直到下次拉取。
 */
final class ExploreQueryStore: LogoutClearable {
    let nearby: MemoryQuery<NearbyPinsKey, NearbyPinsPage>

    /** [activityTypeInvalidations]：每种活动的失效脉冲（各活动类型的事件类型不同，所以传工厂）。 */
    init(repository: ExploreRepository, activityTypeInvalidations: [@Sendable () -> AsyncStream<Void>]) {
        nearby = MemoryQuery(invalidates: {
            let streams = activityTypeInvalidations.map { $0() }
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
                activityTypes: key.activityTypes.isEmpty ? nil : key.activityTypes,
                openSpotsOnly: key.openSpotsOnly ? true : nil,
                sort: key.sort == .distance ? nil : key.sort
            ))
        }
    }

    func overlayView(activityId: String, view: Int) async {
        guard !activityId.isEmpty, view >= 0 else { return }
        await nearby.updateAll { page in
            var page = page
            for index in page.items.indices where page.items[index].id == activityId && page.items[index].view < view {
                page.items[index].view = view
            }
            return page
        }
    }

    func onLogout() async throws {
        await nearby.clear()
    }
}
