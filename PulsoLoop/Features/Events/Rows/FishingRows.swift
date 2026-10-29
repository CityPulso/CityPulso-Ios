import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `FishingOptions.labels()` 一致。 */

extension FishingEventListItem: SportEventItem {
    var sport: LoopSport { .fishing }

    var optionLabels: [Text] {
        [Text(fishingMethod.labelKey), Text(catchPolicy.labelKey), Text(requiresLicense ? "sport_option_requires_license_yes" : "sport_option_requires_license_no")]
    }
}

extension FishingMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .fishing }

    var optionLabels: [Text] {
        [Text(fishingMethod.labelKey), Text(catchPolicy.labelKey), Text(requiresLicense ? "sport_option_requires_license_yes" : "sport_option_requires_license_no")]
    }
}

extension FishingFullEvent: SportFullEvent {
    var sport: LoopSport { .fishing }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(fishingMethod.labelKey), Text(catchPolicy.labelKey), Text(requiresLicense ? "sport_option_requires_license_yes" : "sport_option_requires_license_no")]
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "fish", label: Text("sport_option_fishing_method_label"), value: Text(fishingMethod.labelKey)),
            OptionFact(systemImage: "water.waves", label: Text("sport_option_catch_policy_label"), value: Text(catchPolicy.labelKey)),
            OptionFact(systemImage: "person.text.rectangle", label: Text("sport_option_requires_license_label"), value: Text(requiresLicense ? "sport_option_requires_license_yes" : "sport_option_requires_license_no")),
        ]
    }
}

extension FishingRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
