import Foundation

/** 建筑仓储（Android `BuildingRepository`，WEB `ApiBuildingRepository` 的公开读）。收藏在第 8 组补上。 */
public struct BuildingRepository: Sendable {
    private let api: BuildingAPI

    public init(api: BuildingAPI) {
        self.api = api
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
}
