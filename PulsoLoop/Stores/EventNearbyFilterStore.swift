import Foundation
import PulsoLinkCore

/**
 * 附近活动筛选：活动列表和地图共用，存在设备上，下次打开照样生效（对应 Android `EventNearbyFilterStore`，
 * 存 "loop-event-nearby-filters"）。读不了的旧数据回到默认值。
 */
final class EventNearbyFilterStore: Sendable {
    private static let key = "loop-event-nearby-filters"

    private nonisolated(unsafe) let defaults: UserDefaults
    let filters: StateBroadcast<EventNearbyFilters>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(EventNearbyFilters.self, from: $0) }
        filters = StateBroadcast(stored ?? EventNearbyFilters())
    }

    func set(_ next: EventNearbyFilters) {
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        filters.set(next)
    }

    func reset() {
        set(EventNearbyFilters())
    }
}
