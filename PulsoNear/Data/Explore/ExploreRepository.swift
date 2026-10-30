import PulsoLinkCore

/** 所有活动类型的附近活动针（对应 Android `ExploreRepository`、WEB `ApiExploreRepository`）。 */
struct ExploreRepository: Sendable {
    let publicAPI: ExplorePublicAPI

    func listNearbyPins(_ body: ListNearbyPinsRequest) async throws -> NearbyPinsPage {
        try await publicAPI.listNearbyPins(body).dataOrThrow("ListNearbyPins")
    }
}

extension ExplorePin {
    var locationLat: Double? { geoCoordinate(locationGeojson, index: 1) }
    var locationLng: Double? { geoCoordinate(locationGeojson, index: 0) }
}
