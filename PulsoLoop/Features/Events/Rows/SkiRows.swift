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

extension SkiFullEvent: SportFullEvent {
    var sport: LoopSport { .ski }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(skiDiscipline.labelKey), Text(skiSkillLevel.labelKey), Text(includesLiftTicket ? "sport_option_includes_lift_ticket_yes" : "sport_option_includes_lift_ticket_no")]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "figure.skiing.downhill", label: Text("sport_option_ski_discipline_label"), value: Text(skiDiscipline.labelKey)),
            OptionFact(systemImage: "speedometer", label: Text("sport_option_ski_skill_level_label"), value: Text(skiSkillLevel.labelKey)),
            OptionFact(systemImage: "ticket", label: Text("sport_option_includes_lift_ticket_label"), value: Text(includesLiftTicket ? "sport_option_includes_lift_ticket_yes" : "sport_option_includes_lift_ticket_no")),
        ]
    }
}

extension SkiRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
