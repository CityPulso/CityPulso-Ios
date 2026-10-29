import Foundation
import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `HikingOptions.labels()` 一致。 */

extension HikingEventListItem: SportEventItem {
    var sport: LoopSport { .hiking }

    var optionLabels: [Text] {
        [Text(hikingDifficulty.labelKey), Text(verbatim: localizedFormat("sport_option_distance_km_value", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)))]
            + (elevationGainM.map { [Text(verbatim: localizedFormat("sport_option_elevation_gain_m_value", $0))] } ?? [])
    }
}

extension HikingMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .hiking }

    var optionLabels: [Text] {
        [Text(hikingDifficulty.labelKey), Text(verbatim: localizedFormat("sport_option_distance_km_value", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)))]
            + (elevationGainM.map { [Text(verbatim: localizedFormat("sport_option_elevation_gain_m_value", $0))] } ?? [])
    }
}
