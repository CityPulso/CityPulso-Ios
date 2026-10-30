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

/** 别人主页「参加的」（只要活动字段）。 */
extension FootballProfileRegistrationItem: SportEventItem {
    var sport: LoopSport { .football }

    var optionLabels: [Text] {
        [Text(footballFormat.labelKey), Text(pitchSurface.labelKey), Text(eligibilityDivision.labelKey)]
    }
}

extension FootballFullEvent: SportFullEvent {
    var sport: LoopSport { .football }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(footballFormat.labelKey), Text(pitchSurface.labelKey), Text(eligibilityDivision.labelKey)]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "person.3", label: Text("sport_option_football_format_label"), value: Text(footballFormat.labelKey)),
            OptionFact(systemImage: "leaf", label: Text("sport_option_pitch_surface_label"), value: Text(pitchSurface.labelKey)),
            OptionFact(systemImage: "figure.dress.line.vertical.figure", label: Text("sport_option_eligibility_division_label"), value: Text(eligibilityDivision.labelKey)),
        ]
    }
}

extension FootballRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
