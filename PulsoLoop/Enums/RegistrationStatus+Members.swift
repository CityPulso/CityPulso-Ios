import SwiftUI

extension RegistrationStatus {
    /** 报名状态文字（Android 各处 `when (status)` 选的 `shell_home_status_*`）。 */
    var labelKey: LocalizedStringKey {
        switch self {
        case .participating: "shell_home_status_participating"
        case .waitlisted: "shell_home_status_waitlisted"
        case .pendingExit: "shell_home_status_pending_exit"
        case .exited: "shell_home_status_exited"
        case .awaitingPayment: "shell_home_status_awaiting_payment"
        }
    }
}
