import PulsoLinkCore

/** 球馆仓储（Android `VenueRepository`）：玩家侧浏览球馆、收藏；各运动入口的订场走 [VenueEntryRepository]。 */
struct VenueRepository: Sendable {
    let publicAPI: VenuePublicAPI
    let api: VenueAPI

    func listNearbyVenues(_ body: ListNearbyVenuesRequest) async throws -> NearbyVenuesPage {
        try await publicAPI.listNearbyVenues(body).dataOrThrow("ListNearbyVenues")
    }

    func listMyVenues() async throws -> [MyVenue] {
        try await api.listMyVenues().dataOrThrow("ListMyVenues")
    }

    func getVenue(_ venueId: String) async throws -> VenueDetail {
        try await api.getVenue(venueId: venueId).dataOrThrow("GetVenue")
    }

    func incrementVenueView(_ venueId: String) async throws -> IncrementVenueViewResponse {
        try await api.incrementVenueView(venueId: venueId).dataOrThrow("IncrementVenueView")
    }

    /** 建筑上的球馆；没有时服务端回 200 + `data: null`。 */
    func getVenueByBuilding(_ buildingId: String) async throws -> VenueDetail? {
        try await api.getVenueByBuilding(buildingId: buildingId).data ?? nil
    }

    func listOfferings(_ venueId: String) async throws -> [VenueOffering] {
        try await api.listOfferings(venueId: venueId).dataOrThrow("ListOfferings")
    }

    func listFavorites(_ body: VenueFavoritesRequest) async throws -> ListWithTotal<VenueFavoriteItem> {
        try await api.listFavorites(body).dataOrThrow("ListVenueFavorites")
    }

    func favoriteCounts() async throws -> VenueFavoriteCounts {
        try await api.favoriteCounts().dataOrThrow("VenueFavoriteCounts")
    }

    /** [venueIds] 里哪些收藏了；每批最多 [CheckVenueFavoritesRequest.max] 个分批问。 */
    func checkFavorites(_ venueIds: [String]) async throws -> Set<String> {
        var starred = Set<String>()
        let ids = Array(Set(venueIds))
        for start in stride(from: 0, to: ids.count, by: CheckVenueFavoritesRequest.max) {
            let chunk = Array(ids[start ..< min(start + CheckVenueFavoritesRequest.max, ids.count)])
            starred.formUnion(try await api.checkFavorites(CheckVenueFavoritesRequest(venueIds: chunk)).dataOrThrow("CheckVenueFavorites").venueIds)
        }
        return starred
    }

    func favorite(_ venueId: String) async throws {
        try await api.favorite(FavoriteVenueRequest(venueId: venueId))
    }

    func unfavorite(_ venueId: String) async throws {
        try await api.unfavorite(venueId: venueId)
    }
}

extension NearbyVenuePin {
    var pinLat: Double? { building.locationLat }
    var pinLng: Double? { building.locationLng }
}

extension CheckVenueFavoritesRequest {
    /** 一次最多问 200 个。 */
    static let max = 200
}
