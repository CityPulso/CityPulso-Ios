import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `FootballOptions.labels()` 一致。 */

extension FootballEventListItem: SportEventItem {
    var sport: LoopSport { .football }

    var optionLabels: [Text] {
        [Text(footballFormat.labelKey), Text(pitchSurface.labelKey), Text(eligibilityDivision.labelKey)]
    }
}

extension FootballMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .football }

    var optionLabels: [Text] {
        [Text(footballFormat.labelKey), Text(pitchSurface.labelKey), Text(eligibilityDivision.labelKey)]
    }
}
