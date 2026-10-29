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
