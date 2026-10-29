import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `TableTennisOptions.labels()` 一致。 */

extension TableTennisEventListItem: SportEventItem {
    var sport: LoopSport { .tableTennis }

    var optionLabels: [Text] {
        [Text(verbatim: localizedFormat("sport_option_table_count_value", tableCount)), Text(verbatim: localizedFormat("sport_option_players_per_table_value", playersPerTable)), Text(matchFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }
}

extension TableTennisMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .tableTennis }

    var optionLabels: [Text] {
        [Text(verbatim: localizedFormat("sport_option_table_count_value", tableCount)), Text(verbatim: localizedFormat("sport_option_players_per_table_value", playersPerTable)), Text(matchFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }
}
