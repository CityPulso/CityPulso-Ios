import Foundation

/** 收藏的建筑怎么筛（Android `BuildingFavoritesFilter`）；[near] 只在按距离排序时用。 */
public struct BuildingFavoritesFilter: Hashable, Sendable {
    public var search: String
    public var buildingTypes: [String]
    public var sort: PlaceSort
    public var near: GeoPoint?

    public init(search: String = "", buildingTypes: [String] = [], sort: PlaceSort = .fallback, near: GeoPoint? = nil) {
        self.search = search
        self.buildingTypes = buildingTypes
        self.sort = sort
        self.near = near
    }
}

extension CheckBuildingFavoritesRequest {
    /** 一次最多问 200 个。 */
    public static let max = 200
}

/** 建筑仓储（Android `BuildingRepository`，WEB `ApiBuildingRepository` 的公开读）：附近、单个、收藏。 */
public struct BuildingRepository: Sendable {
    private let api: BuildingAPI
    private let favorites: FavoriteAPI

    public init(api: BuildingAPI, favorites: FavoriteAPI) {
        self.api = api
        self.favorites = favorites
    }

    /** [buildingTypes] 为空时不限类型。 */
    public func listNearbyBuildings(
        lat: Double,
        lng: Double,
        radiusM: Int? = nil,
        search: String? = nil,
        buildingTypes: [String] = [],
        limit: Int? = nil
    ) async throws -> ListWithTotal<BuildingItem> {
        try await api.listNearbyBuildings(
            lat: lat, lng: lng, radiusM: radiusM, search: search,
            buildingTypes: buildingTypes.isEmpty ? nil : buildingTypes.joined(separator: ","), limit: limit
        ).dataOrThrow("ListNearbyBuildings")
    }

    public func getBuilding(id: String) async throws -> BuildingItem {
        try await api.getBuilding(id: id).dataOrThrow("GetBuilding")
    }

    public func listBuildingFavorites(_ filter: BuildingFavoritesFilter, offset: Int, limit: Int) async throws -> ListWithTotal<BuildingFavoriteItem> {
        let search = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await favorites.listBuildingFavorites(BuildingFavoritesRequest(
            offset: offset,
            limit: limit,
            search: search.isEmpty ? nil : search,
            buildingTypes: filter.buildingTypes.isEmpty ? nil : filter.buildingTypes,
            sort: filter.sort,
            near: filter.sort == .nearest ? filter.near : nil
        )).dataOrThrow("ListBuildingFavorites")
    }

    /** [buildingTypes] 类型的收藏建筑（空 = 所有类型），总数和每种类型的数。 */
    public func buildingFavoriteCounts(buildingTypes: [String] = []) async throws -> BuildingFavoriteCounts {
        try await favorites.buildingFavoriteCounts(buildingTypes: buildingTypes.isEmpty ? nil : buildingTypes.joined(separator: ",")).dataOrThrow("BuildingFavoriteCounts")
    }

    /** [buildingIds] 里哪些收藏了；每批最多 [CheckBuildingFavoritesRequest.max] 个。 */
    public func checkBuildingFavorites(_ buildingIds: [String]) async throws -> Set<String> {
        var starred = Set<String>()
        let ids = Array(Set(buildingIds))
        for start in stride(from: 0, to: ids.count, by: CheckBuildingFavoritesRequest.max) {
            let chunk = Array(ids[start ..< min(start + CheckBuildingFavoritesRequest.max, ids.count)])
            starred.formUnion(try await favorites.checkBuildingFavorites(CheckBuildingFavoritesRequest(buildingIds: chunk)).dataOrThrow("CheckBuildingFavorites").buildingIds)
        }
        return starred
    }

    public func favoriteBuilding(_ buildingId: String) async throws {
        try await favorites.favoriteBuilding(FavoriteBuildingRequest(buildingId: buildingId))
    }

    public func unfavoriteBuilding(_ buildingId: String) async throws {
        try await favorites.unfavoriteBuilding(buildingId: buildingId)
    }
}
