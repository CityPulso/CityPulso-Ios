import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `BasketballOptions.labels()` 一致。 */

extension BasketballEventListItem: SportEventItem {
    var sport: LoopSport { .basketball }

    var optionLabels: [Text] {
        [Text(verbatim: localizedFormat("sport_option_court_count_value", courtCount)), Text(basketballFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }
}

extension BasketballMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .basketball }

    var optionLabels: [Text] {
        [Text(verbatim: localizedFormat("sport_option_court_count_value", courtCount)), Text(basketballFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }
}
