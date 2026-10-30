import Foundation
import PulsoLinkCore

/** Explore 图层开关与门店搜索距离（Android `ExploreLayerSettings`，WEB `stores/explore.ts`）。 */
struct ExploreLayerSettings: Codable, Hashable, Sendable {
    var showActivityLayer = true
    var showVenueLayer = true
    var venueRadiusMode: VenueRadiusMode = .fallback
    /** MULTIPLIER：门店半径 = 活动半径 × 此值。 */
    var venueRadiusMultiplier = 2.0
    /** FIXED：门店半径（km）。 */
    var venueRadiusFixedKm = 10

    /** 活动搜索半径（米）对应的门店搜索半径（米）。 */
    func venueRadiusM(_ activityRadiusM: Int) -> Int {
        switch venueRadiusMode {
        case .fixed: venueRadiusFixedKm * 1000
        case .multiplier: Int(Double(activityRadiusM) * venueRadiusMultiplier)
        }
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let defaults = ExploreLayerSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showActivityLayer = (try? container.decodeIfPresent(Bool.self, forKey: .showActivityLayer)) ?? defaults.showActivityLayer
        showVenueLayer = (try? container.decodeIfPresent(Bool.self, forKey: .showVenueLayer)) ?? defaults.showVenueLayer
        venueRadiusMode = (try? container.decodeIfPresent(VenueRadiusMode.self, forKey: .venueRadiusMode)) ?? defaults.venueRadiusMode
        venueRadiusMultiplier = (try? container.decodeIfPresent(Double.self, forKey: .venueRadiusMultiplier)) ?? defaults.venueRadiusMultiplier
        venueRadiusFixedKm = (try? container.decodeIfPresent(Int.self, forKey: .venueRadiusFixedKm)) ?? defaults.venueRadiusFixedKm
    }
}

/** 存 "near-explore-layers"，单个字段读不了就用默认值。 */
final class ExploreLayerStore: Sendable {
    private static let key = "near-explore-layers"

    private nonisolated(unsafe) let defaults: UserDefaults
    let settings: StateBroadcast<ExploreLayerSettings>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ExploreLayerSettings.self, from: $0) }
        settings = StateBroadcast(stored ?? ExploreLayerSettings())
    }

    func update(_ transform: (inout ExploreLayerSettings) -> Void) {
        var next = settings.value
        transform(&next)
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        settings.set(next)
    }
}
