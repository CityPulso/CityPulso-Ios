import Foundation

/** 活动选点自动关联建筑的半径（米），对齐 WEB `BUILDING_AUTO_LINK_RADIUS_M`。 */
public let buildingAutoLinkRadiusM = 500

/** Building 域门面（Android `BuildingService`）：页面不直接碰 [BuildingRepository]。 */
public struct BuildingService: Sendable {
    private let buildings: BuildingRepository

    public init(buildings: BuildingRepository) {
        self.buildings = buildings
    }

    public func listNearbyBuildings(
        lat: Double,
        lng: Double,
        radiusM: Int? = nil,
        search: String? = nil,
        buildingTypes: [String] = [],
        limit: Int? = nil
    ) async throws -> ListWithTotal<BuildingItem> {
        try await buildings.listNearbyBuildings(lat: lat, lng: lng, radiusM: radiusM, search: search, buildingTypes: buildingTypes, limit: limit)
    }

    public func getBuilding(id: String) async throws -> BuildingItem {
        try await buildings.getBuilding(id: id)
    }
}
