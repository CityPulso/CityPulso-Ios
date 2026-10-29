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

extension BaseballFullEvent: SportFullEvent {
    var sport: LoopSport { .baseball }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(baseballVariant.labelKey), Text(verbatim: localizedFormat("sport_option_innings_value", innings))]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "baseball", label: Text("sport_option_baseball_variant_label"), value: Text(baseballVariant.labelKey)),
            OptionFact(systemImage: "timer", label: Text("sport_option_innings_label"), value: Text(verbatim: localizedFormat("sport_option_innings_value", innings))),
        ]
    }
}

extension BaseballRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
