import Foundation
import PulsoLinkCore

/**
 * 附近活动筛选：活动列表和地图共用，存在设备上，下次打开照样生效（对应 Android `ActivityNearbyFilterStore`，
 * 存 "near-activity-nearby-filters"）。读不了的旧数据回到默认值。
 */
final class ActivityNearbyFilterStore: Sendable {
    private static let key = "near-activity-nearby-filters"

    private nonisolated(unsafe) let defaults: UserDefaults
    let filters: StateBroadcast<ActivityNearbyFilters>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ActivityNearbyFilters.self, from: $0) }
        filters = StateBroadcast(stored ?? ActivityNearbyFilters())
    }

    func set(_ next: ActivityNearbyFilters) {
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        filters.set(next)
    }

    func reset() {
        set(ActivityNearbyFilters())
    }
}
