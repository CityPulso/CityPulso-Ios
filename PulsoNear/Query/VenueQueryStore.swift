import PulsoLinkCore

/** 某活动类型入口某一天的可用性。 */
struct VenueAvailabilityKey: Hashable, Sendable {
    var venueId: String
    var activityType: VenueActivityType
    var date: String
    var profileId: String
}

/** 我的订场的一次有上限的读取（日程、活动中心）；订场页本身分页。 */
struct MySpaceBookingsKey: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var upcoming: Bool
    var limit: Int
}

/** 门店在某个身份下的视图。 */
struct VenueKey: Hashable, Sendable {
    var venueId: String
    var profileId: String
}

struct NearbyVenuesKey: Hashable, Sendable {
    var longitude: Double
    var latitude: Double
    /** 地图视野半径；nil = 不限距离（搜索列表：全部，按远近排）。 */
    var radiusM: Int?
    var search: String?
    /** 空 = 不按活动类型筛选。 */
    var activityTypes: Set<VenueActivityType> = []
    var openNow = false
    var acceptsMembership = false
    var acceptsPlatform = false
    var maxHourlyPrice: Double?
    /** 设施图标 key；空 = 不按设施筛选。 */
    var amenities: [String] = []
    var sort: VenueNearbySort = .distance
    var offset = 0
    var limit = 100
    var summary = false
}

/**
 * 门店读接口的缓存（对应 Android `VenueQueryStore`；各活动类型入口那几项在 `<ActivityType>VenueQueryStore`）。任何门店写操作（[VenueEventBus]）全部失效。
 * 浏览次数（计数接口的返回）直接盖到缓存的详情和地图针上。
 */
final class VenueQueryStore: LogoutClearable {
    let detail: MemoryQuery<VenueKey, VenueDetail>
    let offerings: MemoryQuery<VenueKey, [VenueOffering]>
    let nearby: MemoryQuery<NearbyVenuesKey, NearbyVenuesPage>
    /** 门店游戏库（桌游门店详情里列出的桌游）。 */
    let boardGameTitles: MemoryQuery<VenueKey, [BoardGameTitle]>

    init(repository: VenueRepository, boardGames: BoardGameEntryAPI, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        detail = MemoryQuery(invalidates: invalidates) { key in try await repository.getVenue(key.venueId) }
        offerings = MemoryQuery(invalidates: invalidates) { key in try await repository.listOfferings(key.venueId) }
        boardGameTitles = MemoryQuery(invalidates: invalidates) { key in try await boardGames.listTitles(venueId: key.venueId).dataOrThrow("ListBoardGameTitles") }
        nearby = MemoryQuery(invalidates: invalidates) { key in
            try await repository.listNearbyVenues(ListNearbyVenuesRequest(
                near: GeoNearQuery(longitude: key.longitude, latitude: key.latitude, radiusM: key.radiusM),
                search: key.search,
                activityTypes: key.activityTypes.isEmpty ? nil : key.activityTypes.sorted { $0.rawValue < $1.rawValue },
                openNow: key.openNow ? true : nil,
                acceptsMembership: key.acceptsMembership ? true : nil,
                acceptsPlatform: key.acceptsPlatform ? true : nil,
                maxHourlyPrice: key.maxHourlyPrice,
                amenities: key.amenities.isEmpty ? nil : key.amenities,
                sort: key.sort == .distance ? nil : key.sort,
                offset: key.offset,
                limit: key.limit,
                summary: key.summary
            ))
        }
    }

    /** 计数接口回来的新浏览次数，盖到缓存的详情和附近针上（只增不减）。 */
    func overlayView(venueId: String, view: Int) async {
        guard !venueId.isEmpty, view > 0 else { return }
        await detail.updateAll { venue in
            guard venue.id == venueId, venue.view < view else { return venue }
            var venue = venue
            venue.view = view
            return venue
        }
        await nearby.updateAll { page in
            var page = page
            for index in page.items.indices where page.items[index].id == venueId && page.items[index].view < view {
                page.items[index].view = view
            }
            return page
        }
    }

    func onLogout() async throws {
        await detail.clear()
        await offerings.clear()
        await nearby.clear()
        await boardGameTitles.clear()
    }
}
