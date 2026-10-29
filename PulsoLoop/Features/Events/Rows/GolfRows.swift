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

extension GolfFullEvent: SportFullEvent {
    var sport: LoopSport { .golf }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(golfHoles.labelKey), Text(verbatim: localizedFormat("sport_option_group_count_value", groupCount)), Text(verbatim: localizedFormat("sport_option_players_per_group_value", playersPerGroup))]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "figure.golf", label: Text("sport_option_golf_holes_label"), value: Text(golfHoles.labelKey)),
            OptionFact(systemImage: "person.3", label: Text("sport_option_group_count_label"), value: Text(verbatim: localizedFormat("sport_option_group_count_value", groupCount))),
            OptionFact(systemImage: "number", label: Text("sport_option_players_per_group_label"), value: Text(verbatim: localizedFormat("sport_option_players_per_group_value", playersPerGroup))),
        ]
    }
}

extension GolfRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
