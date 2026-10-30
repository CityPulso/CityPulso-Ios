import Foundation
import PulsoLinkCore

/**
 * 附近球馆筛选：球馆列表和地图共用，存在设备上，下次打开照样生效（对应 Android `VenueNearbyFilterStore`，
 * 存 "loop-venue-nearby-filters"）。读不了的旧数据回到默认值。
 */
final class VenueNearbyFilterStore: Sendable {
    private static let key = "loop-venue-nearby-filters"

    private nonisolated(unsafe) let defaults: UserDefaults
    let filters: StateBroadcast<VenueNearbyFilters>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(VenueNearbyFilters.self, from: $0) }
        filters = StateBroadcast(stored ?? VenueNearbyFilters())
    }

    func set(_ next: VenueNearbyFilters) {
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        filters.set(next)
    }

    func reset() {
        set(VenueNearbyFilters())
    }
}
