import PulsoLinkCore
import PulsoLinkUI
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

extension BasketballFullEvent: SportFullEvent {
    var sport: LoopSport { .basketball }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(verbatim: localizedFormat("sport_option_court_count_value", courtCount)), Text(basketballFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "sportscourt", label: Text("sport_option_court_count_label"), value: Text(verbatim: localizedFormat("sport_option_court_count_value", courtCount))),
            OptionFact(systemImage: "person.3", label: Text("sport_option_basketball_format_label"), value: Text(basketballFormat.labelKey)),
            OptionFact(systemImage: "figure.dress.line.vertical.figure", label: Text("sport_option_eligibility_division_label"), value: Text(eligibilityDivision.labelKey)),
        ]
    }
}

extension BasketballRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
