import PulsoLinkCore
import SwiftUI

extension BadmintonEventListItem: SportEventItem {
    var sport: LoopSport { .badminton }

    var optionLabels: [Text] {
        racketOptionLabels(matchFormat: matchFormat, eligibilityDivision: eligibilityDivision, courtCount: courtCount, playersPerCourt: playersPerCourt)
    }
}

extension BadmintonMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .badminton }

    var optionLabels: [Text] {
        racketOptionLabels(matchFormat: matchFormat, eligibilityDivision: eligibilityDivision, courtCount: courtCount, playersPerCourt: playersPerCourt)
    }
}

/** 别人主页「参加的」（只要活动字段）。 */
extension BadmintonProfileRegistrationItem: SportEventItem {
    var sport: LoopSport { .badminton }

    var optionLabels: [Text] {
        racketOptionLabels(matchFormat: matchFormat, eligibilityDivision: eligibilityDivision, courtCount: courtCount, playersPerCourt: playersPerCourt)
    }
}

extension BadmintonFullEvent: SportFullEvent {
    var sport: LoopSport { .badminton }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(matchFormat.labelKey), Text(eligibilityDivision.labelKey)]
    }

    var facts: [OptionFact] {
        racketFacts(matchFormat: matchFormat, eligibilityDivision: eligibilityDivision, courtCount: courtCount, playersPerCourt: playersPerCourt)
    }
}

extension BadmintonRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
