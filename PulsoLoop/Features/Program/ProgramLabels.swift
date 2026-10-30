import SwiftUI

/* 课程 / 私教闭集 → 文案（Android `features/program/ProgramLabels.kt`）。 */

/** 课程级别。 */
extension CourseLevel {
    var labelKey: LocalizedStringKey {
        switch self {
        case .allLevels: "program_level_all"
        case .beginner: "program_level_beginner"
        case .intermediate: "program_level_intermediate"
        case .advanced: "program_level_advanced"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .allLevels: "program_level_all"
        case .beginner: "program_level_beginner"
        case .intermediate: "program_level_intermediate"
        case .advanced: "program_level_advanced"
        }
    }
}

/** 课程付款方式。 */
extension CoursePaymentMethod {
    var labelKey: LocalizedStringKey {
        switch self {
        case .phone: "program_method_phone"
        case .offline: "program_method_offline"
        case .platform: "program_method_platform"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .phone: "program_method_phone"
        case .offline: "program_method_offline"
        case .platform: "program_method_platform"
        }
    }
}

/** 课程报名状态。 */
extension CourseEnrollmentStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "program_status_pending"
        case .awaitingPayment: "program_status_awaiting_payment"
        case .enrolled: "program_status_enrolled"
        case .canceled: "program_status_canceled"
        case .expired: "program_status_expired"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .pending: "program_status_pending"
        case .awaitingPayment: "program_status_awaiting_payment"
        case .enrolled: "program_status_enrolled"
        case .canceled: "program_status_canceled"
        case .expired: "program_status_expired"
        }
    }
}

/** 私教课在球馆这边的进度。 */
extension CoachingVenueState {
    var labelKey: LocalizedStringKey {
        switch self {
        case .draft: "program_coaching_draft"
        case .pendingVenue: "program_coaching_pending_venue"
        case .pendingPayment: "program_coaching_pending_payment"
        case .confirmed: "program_coaching_confirmed"
        case .rejected: "program_coaching_rejected"
        case .canceled: "program_coaching_canceled"
        case .completed: "program_coaching_completed"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .draft: "program_coaching_draft"
        case .pendingVenue: "program_coaching_pending_venue"
        case .pendingPayment: "program_coaching_pending_payment"
        case .confirmed: "program_coaching_confirmed"
        case .rejected: "program_coaching_rejected"
        case .canceled: "program_coaching_canceled"
        case .completed: "program_coaching_completed"
        }
    }
}

/** 私教学员状态。 */
extension CoachingParticipantStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .invited: "program_participant_invited"
        case .accepted: "program_participant_accepted"
        case .declined: "program_participant_declined"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .invited: "program_participant_invited"
        case .accepted: "program_participant_accepted"
        case .declined: "program_participant_declined"
        }
    }
}

/** 私教付款状态。 */
extension CoachingPaymentStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .unpaid: "program_payment_unpaid"
        case .awaitingPayment: "program_payment_awaiting"
        case .paid: "program_payment_paid"
        case .waived: "program_payment_waived"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .unpaid: "program_payment_unpaid"
        case .awaitingPayment: "program_payment_awaiting"
        case .paid: "program_payment_paid"
        case .waived: "program_payment_waived"
        }
    }
}

/** 私教形式。 */
extension CoachingServiceFormat {
    var labelKey: LocalizedStringKey {
        switch self {
        case .oneOnOne: "program_format_one_on_one"
        case .oneOnTwo: "program_format_one_on_two"
        case .smallGroup: "program_format_small_group"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .oneOnOne: "program_format_one_on_one"
        case .oneOnTwo: "program_format_one_on_two"
        case .smallGroup: "program_format_small_group"
        }
    }
}

/** 和球馆的合作状态。 */
extension VenueCoachStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "program_partner_pending"
        case .active: "program_partner_active"
        case .rejected: "program_partner_rejected"
        case .ended: "program_partner_ended"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .pending: "program_partner_pending"
        case .active: "program_partner_active"
        case .rejected: "program_partner_rejected"
        case .ended: "program_partner_ended"
        }
    }
}

/** 教练报酬状态。 */
extension CoachCompensationStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .owed: "program_compensation_owed"
        case .settled: "program_compensation_settled"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .owed: "program_compensation_owed"
        case .settled: "program_compensation_settled"
        }
    }
}
