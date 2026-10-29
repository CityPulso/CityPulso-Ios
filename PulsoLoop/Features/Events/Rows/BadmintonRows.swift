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
