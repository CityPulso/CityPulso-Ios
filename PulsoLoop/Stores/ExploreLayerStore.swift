import Foundation
import PulsoLinkCore

/** Explore 图层开关与球馆搜索距离（Android `ExploreLayerSettings`，WEB `stores/explore.ts`）。 */
struct ExploreLayerSettings: Codable, Hashable, Sendable {
    var showEventLayer = true
    var showVenueLayer = true
    /** 赛事（每个已同意的球馆一个点）；搜索半径与球馆图层相同。 */
    var showTournamentLayer = true
    var venueRadiusMode: VenueRadiusMode = .fallback
    /** MULTIPLIER：球馆半径 = 活动半径 × 此值。 */
    var venueRadiusMultiplier = 2.0
    /** FIXED：球馆半径（km）。 */
    var venueRadiusFixedKm = 10

    /** 活动搜索半径（米）对应的球馆搜索半径（米）。 */
    func venueRadiusM(_ eventRadiusM: Int) -> Int {
        switch venueRadiusMode {
        case .fixed: venueRadiusFixedKm * 1000
        case .multiplier: Int(Double(eventRadiusM) * venueRadiusMultiplier)
        }
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let defaults = ExploreLayerSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showEventLayer = (try? container.decodeIfPresent(Bool.self, forKey: .showEventLayer)) ?? defaults.showEventLayer
        showVenueLayer = (try? container.decodeIfPresent(Bool.self, forKey: .showVenueLayer)) ?? defaults.showVenueLayer
        showTournamentLayer = (try? container.decodeIfPresent(Bool.self, forKey: .showTournamentLayer)) ?? defaults.showTournamentLayer
        venueRadiusMode = (try? container.decodeIfPresent(VenueRadiusMode.self, forKey: .venueRadiusMode)) ?? defaults.venueRadiusMode
        venueRadiusMultiplier = (try? container.decodeIfPresent(Double.self, forKey: .venueRadiusMultiplier)) ?? defaults.venueRadiusMultiplier
        venueRadiusFixedKm = (try? container.decodeIfPresent(Int.self, forKey: .venueRadiusFixedKm)) ?? defaults.venueRadiusFixedKm
    }
}

/** 存 "loop-explore-layers"，单个字段读不了就用默认值。 */
final class ExploreLayerStore: Sendable {
    private static let key = "loop-explore-layers"

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
