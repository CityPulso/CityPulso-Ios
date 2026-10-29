import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `BaseballOptions.labels()` 一致。 */

extension BaseballEventListItem: SportEventItem {
    var sport: LoopSport { .baseball }

    var optionLabels: [Text] {
        [Text(baseballVariant.labelKey), Text(verbatim: localizedFormat("sport_option_innings_value", innings))]
    }
}

extension BaseballMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .baseball }

    var optionLabels: [Text] {
        [Text(baseballVariant.labelKey), Text(verbatim: localizedFormat("sport_option_innings_value", innings))]
    }
}
