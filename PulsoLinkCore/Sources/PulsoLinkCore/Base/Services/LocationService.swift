import Foundation

/** Location 域门面（Android `LocationService`）：页面不直接碰 [LocationRepository]。 */
public struct LocationService: Sendable {
    private let location: LocationRepository

    public init(location: LocationRepository) {
        self.location = location
    }

    public func reverseGeocode(lat: Double, lng: Double) async throws -> ReverseGeocodeOutput {
        try await location.reverseGeocode(lat: lat, lng: lng)
    }

    public func searchLocation(query: String, lat: Double, lng: Double) async throws -> SearchTextOutput {
        try await location.searchLocation(query: query, lat: lat, lng: lng)
    }

    public func geocodeLocation(query: String) async throws -> GeocodeOutput {
        try await location.geocodeLocation(query: query)
    }
}
