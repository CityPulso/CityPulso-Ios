import Foundation

/** 位置仓储（Android `LocationRepository`）：反向地理编码、搜索、正向地理编码，都要登录。 */
public struct LocationRepository: Sendable {
    private let api: LocationAPI

    public init(api: LocationAPI) {
        self.api = api
    }

    public func reverseGeocode(lat: Double, lng: Double) async throws -> ReverseGeocodeOutput {
        try await api.reverseGeocode(lat: lat, lng: lng).dataOrThrow("ReverseGeocode")
    }

    public func searchLocation(query: String, lat: Double, lng: Double) async throws -> SearchTextOutput {
        try await api.searchLocation(query: query, lat: lat, lng: lng).dataOrThrow("SearchLocation")
    }

    public func geocodeLocation(query: String) async throws -> GeocodeOutput {
        try await api.geocodeLocation(query: query).dataOrThrow("GeocodeLocation")
    }
}

extension SearchTextResultItem {
    /** 结果点的 (经度, 纬度)：先看 position，再看第一个出入口（Android `resolvedPositionLngLat`）。 */
    public var resolvedPositionLngLat: (longitude: Double, latitude: Double)? {
        guard let position = position ?? accessPoints?.first?.position, position.count >= 2,
              position[0].isFinite, position[1].isFinite
        else { return nil }
        return (position[0], position[1])
    }

    /** 地址全称，没有就用标题。 */
    public var resolvedLabel: String {
        let label = address?.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : label
    }
}
