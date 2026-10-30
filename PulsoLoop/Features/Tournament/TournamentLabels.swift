import SwiftUI

/* Android `features/tournament/TournamentLabels.kt`。 */

extension TournamentStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .draft: "tournament_status_draft"
        case .published: "tournament_status_published"
        case .inProgress: "tournament_status_in_progress"
        case .completed: "tournament_status_completed"
        case .canceled: "tournament_status_canceled"
        }
    }
}
