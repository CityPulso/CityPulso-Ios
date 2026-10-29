import Foundation
import PulsoLinkCore
import SwiftUI

/* 标签顺序与 Android `HikingOptions.labels()` 一致。 */

extension HikingEventListItem: SportEventItem {
    var sport: LoopSport { .hiking }

    var optionLabels: [Text] {
        [Text(hikingDifficulty.labelKey), Text(verbatim: localizedFormat("sport_option_distance_km_value", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)))]
            + (elevationGainM.map { [Text(verbatim: localizedFormat("sport_option_elevation_gain_m_value", $0))] } ?? [])
    }
}

extension HikingMyRegistrationItem: SportRegistrationItem {
    var sport: LoopSport { .hiking }

    var optionLabels: [Text] {
        [Text(hikingDifficulty.labelKey), Text(verbatim: localizedFormat("sport_option_distance_km_value", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)))]
            + (elevationGainM.map { [Text(verbatim: localizedFormat("sport_option_elevation_gain_m_value", $0))] } ?? [])
    }
}

extension HikingFullEvent: SportFullEvent {
    var sport: LoopSport { .hiking }

    var paymentMethodList: [EventPaymentMethod] {
        paymentMethods.compactMap { method in
            EventPaymentKind(rawValue: method.method.rawValue).map { EventPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var equipmentList: [EventEquipment] {
        equipment.map { EventEquipment(name: $0.name, icon: $0.icon) }
    }

    var optionLabels: [Text] {
        [Text(hikingDifficulty.labelKey), Text(verbatim: localizedFormat("sport_option_distance_km_value", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)))]
            + (elevationGainM.map { [Text(verbatim: localizedFormat("sport_option_elevation_gain_m_value", $0))] } ?? [])
    }

    var facts: [OptionFact] {
        [
            OptionFact(systemImage: "speedometer", label: Text("sport_option_hiking_difficulty_label"), value: Text(hikingDifficulty.labelKey)),
            OptionFact(systemImage: "point.topleft.down.to.point.bottomright.curvepath", label: Text("sport_option_distance_km_label"), value: Text(verbatim: localizedFormat("sport_option_distance_km_value", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)))),
            OptionFact(systemImage: "mountain.2", label: Text("sport_option_elevation_gain_m_label"), value: elevationGainM.map { Text(verbatim: localizedFormat("sport_option_elevation_gain_m_value", $0)) } ?? Text("sport_option_elevation_gain_m_empty")),
        ]
    }
}

extension HikingRegistration: SportRegistration {
    var refund: EventRefundStatus? {
        refundStatus.flatMap { EventRefundStatus(rawValue: $0.rawValue) }
    }
}
