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

extension TableTennisFullEvent: SportFullEvent {
    var sport: LoopSport { .tableTennis }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(verbatim: localizedFormat("sport_option_table_count_value", tableCount)), Text(verbatim: localizedFormat("sport_option_players_per_table_value", playersPerTable)), Text(matchFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "table.furniture", label: Text("sport_option_table_count_label"), value: Text(verbatim: localizedFormat("sport_option_table_count_value", tableCount))),
            OptionFact(systemImage: "number", label: Text("sport_option_players_per_table_label"), value: Text(verbatim: localizedFormat("sport_option_players_per_table_value", playersPerTable))),
            OptionFact(systemImage: "figure.table.tennis", label: Text("sport_option_match_format_label"), value: Text(matchFormat.labelKey)),
            OptionFact(systemImage: "figure.dress.line.vertical.figure", label: Text("sport_option_eligibility_division_label"), value: Text(eligibilityDivision.labelKey)),
        ]
    }
}

extension TableTennisRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
