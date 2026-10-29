import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `GolfOptions.labels()` 一致。 */

extension GolfEventListItem: SportEventItem {
    var sport: LoopSport { .golf }

    var optionLabels: [Text] {
        [Text(golfHoles.labelKey), Text(verbatim: localizedFormat("sport_option_group_count_value", groupCount)), Text(verbatim: localizedFormat("sport_option_players_per_group_value", playersPerGroup))]
    }
}

extension GolfMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .golf }

    var optionLabels: [Text] {
        [Text(golfHoles.labelKey), Text(verbatim: localizedFormat("sport_option_group_count_value", groupCount)), Text(verbatim: localizedFormat("sport_option_players_per_group_value", playersPerGroup))]
    }
}
