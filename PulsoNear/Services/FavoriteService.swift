import PulsoLinkCore

/** 收藏的门店怎么筛（Android `VenueFavoritesFilter`）；[near] 只在按距离排序时用。 */
struct VenueFavoritesFilter: Hashable, Sendable {
    var search = ""
    var activityType: VenueActivityType?
    var sort: PlaceSort = .fallback
    var near: GeoPoint?
}

/** 收藏门面（Android `FavoriteService`）：PulsoLink 的建筑 + Near 的门店。每次切换都通知 [changes]。 */
struct FavoriteService: Sendable {
    let buildings: BuildingRepository
    let venues: VenueRepository
    let changes = EventBroadcast<Void>()

    /** 符合 [filter] 的收藏门店，分页；切换收藏后重拉。 */
    @MainActor
    func pageVenues(_ filter: VenueFavoritesFilter) -> PagedList<VenueFavoriteItem, Int> {
        let venues = venues
        let changes = changes
        return .offset(invalidates: { changes.signals { _ in true } }) { offset, limit in
            let search = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await venues.listFavorites(VenueFavoritesRequest(
                offset: offset,
                limit: limit,
                search: search.isEmpty ? nil : search,
                activityTypes: filter.activityType.map { [$0] },
                sort: filter.sort,
                near: filter.sort == .nearest ? filter.near.map { GeoNearQuery(longitude: $0.longitude, latitude: $0.latitude) } : nil
            ))
        }
    }

    /** 符合 [filter] 的收藏建筑，分页；切换收藏后重拉。 */
    @MainActor
    func pageBuildings(_ filter: BuildingFavoritesFilter) -> PagedList<BuildingFavoriteItem, Int> {
        let buildings = buildings
        let changes = changes
        return .offset(invalidates: { changes.signals { _ in true } }) { offset, limit in
            try await buildings.listBuildingFavorites(filter, offset: offset, limit: limit)
        }
    }

    /** 所有收藏的门店，以及每种活动有几家。 */
    func venueCounts() async throws -> VenueFavoriteCounts {
        try await venues.favoriteCounts()
    }

    /** Near 地点类型的收藏建筑，以及每种有几个。 */
    func buildingCounts() async throws -> BuildingFavoriteCounts {
        try await buildings.buildingFavoriteCounts(buildingTypes: BuildingType.near.map(\.rawValue))
    }

    /** [venueIds] 里哪些收藏了（列表一次标很多行，一个请求不是一行一个）。 */
    func favoriteVenueIds(_ venueIds: [String]) async throws -> Set<String> {
        venueIds.isEmpty ? [] : try await venues.checkFavorites(venueIds)
    }

    func isFavorite(_ target: FavoriteTarget, id: String) async throws -> Bool {
        switch target {
        case .venue: try await venues.checkFavorites([id]).contains(id)
        case .building: try await buildings.checkBuildingFavorites([id]).contains(id)
        }
    }

    func setFavorite(_ target: FavoriteTarget, id: String, favorite: Bool) async throws {
        switch target {
        case .venue: if favorite { try await venues.favorite(id) } else { try await venues.unfavorite(id) }
        case .building: if favorite { try await buildings.favoriteBuilding(id) } else { try await buildings.unfavoriteBuilding(id) }
        }
        changes.emit(())
    }
}
