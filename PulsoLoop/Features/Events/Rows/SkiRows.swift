import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `SkiOptions.labels()` 一致。 */

extension SkiEventListItem: SportEventItem {
    var sport: LoopSport { .ski }

    var optionLabels: [Text] {
        [Text(skiDiscipline.labelKey), Text(skiSkillLevel.labelKey), Text(includesLiftTicket ? "sport_option_includes_lift_ticket_yes" : "sport_option_includes_lift_ticket_no")]
    }
}

extension SkiMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .ski }

    var optionLabels: [Text] {
        [Text(skiDiscipline.labelKey), Text(skiSkillLevel.labelKey), Text(includesLiftTicket ? "sport_option_includes_lift_ticket_yes" : "sport_option_includes_lift_ticket_no")]
    }
}
