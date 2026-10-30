import PulsoLinkCore

/** 某运动入口某一天的可用性。 */
struct VenueAvailabilityKey: Hashable, Sendable {
    var venueId: String
    var sport: VenueSport
    var date: String
    var profileId: String
}

/** 我的订场的一次有上限的读取（日程、活动中心）；订场页本身分页。 */
struct MyCourtBookingsKey: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var upcoming: Bool
    var limit: Int
}

/** 球馆在某个身份下的视图。 */
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
    /** 空 = 不按运动筛选。 */
    var sports: Set<VenueSport> = []
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
 * 球馆读接口的缓存（对应 Android `VenueQueryStore`；各运动入口那几项在 `<Sport>VenueQueryStore`）。任何球馆写操作（[VenueEventBus]）全部失效。
 * 浏览次数（计数接口的返回）直接盖到缓存的详情和地图针上。
 */
final class VenueQueryStore: LogoutClearable {
    let detail: MemoryQuery<VenueKey, VenueDetail>
    let offerings: MemoryQuery<VenueKey, [VenueOffering]>
    let nearby: MemoryQuery<NearbyVenuesKey, NearbyVenuesPage>

    init(repository: VenueRepository, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        detail = MemoryQuery(invalidates: invalidates) { key in try await repository.getVenue(key.venueId) }
        offerings = MemoryQuery(invalidates: invalidates) { key in try await repository.listOfferings(key.venueId) }
        nearby = MemoryQuery(invalidates: invalidates) { key in
            try await repository.listNearbyVenues(ListNearbyVenuesRequest(
                near: GeoNearQuery(longitude: key.longitude, latitude: key.latitude, radiusM: key.radiusM),
                search: key.search,
                sports: key.sports.isEmpty ? nil : key.sports.sorted { $0.rawValue < $1.rawValue },
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
    }
}
