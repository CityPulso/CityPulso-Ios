import Foundation
import PulsoLinkCore
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

    var labelResource: String.LocalizationValue {
        switch self {
        case .draft: "tournament_status_draft"
        case .published: "tournament_status_published"
        case .inProgress: "tournament_status_in_progress"
        case .completed: "tournament_status_completed"
        case .canceled: "tournament_status_canceled"
        }
    }
}

extension TournamentDivisionFormat {
    var labelKey: LocalizedStringKey {
        switch self {
        case .singles: "tournament_format_singles"
        case .doubles: "tournament_format_doubles"
        case .team: "tournament_format_team"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .singles: "tournament_format_singles"
        case .doubles: "tournament_format_doubles"
        case .team: "tournament_format_team"
        }
    }
}

extension TournamentPaymentMethod {
    var labelKey: LocalizedStringKey {
        switch self {
        case .platform: "program_method_platform"
        case .phone: "program_method_phone"
        case .offline: "program_method_offline"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .platform: "program_method_platform"
        case .phone: "program_method_phone"
        case .offline: "program_method_offline"
        }
    }
}

extension TournamentEntryStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .forming: "tournament_entry_forming"
        case .pending: "tournament_entry_pending"
        case .awaitingPayment: "tournament_entry_awaiting_payment"
        case .registered: "tournament_entry_registered"
        case .waitlisted: "tournament_entry_waitlisted"
        case .withdrawn: "tournament_entry_withdrawn"
        case .canceled: "tournament_entry_canceled"
        case .expired: "tournament_entry_expired"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .forming: "tournament_entry_forming"
        case .pending: "tournament_entry_pending"
        case .awaitingPayment: "tournament_entry_awaiting_payment"
        case .registered: "tournament_entry_registered"
        case .waitlisted: "tournament_entry_waitlisted"
        case .withdrawn: "tournament_entry_withdrawn"
        case .canceled: "tournament_entry_canceled"
        case .expired: "tournament_entry_expired"
        }
    }
}

extension TournamentMatchStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .scheduled: "tournament_match_scheduled"
        case .inProgress: "tournament_match_live"
        case .completed: "tournament_match_final"
        case .walkover: "tournament_match_walkover"
        case .canceled: "tournament_match_canceled"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .scheduled: "tournament_match_scheduled"
        case .inProgress: "tournament_match_live"
        case .completed: "tournament_match_final"
        case .walkover: "tournament_match_walkover"
        case .canceled: "tournament_match_canceled"
        }
    }
}

extension TournamentPrizeType {
    var labelKey: LocalizedStringKey {
        switch self {
        case .cash: "tournament_prize_cash"
        case .membership: "tournament_prize_membership"
        case .bundle: "tournament_prize_bundle"
        case .physical: "tournament_prize_physical"
        case .other: "tournament_prize_other"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .cash: "tournament_prize_cash"
        case .membership: "tournament_prize_membership"
        case .bundle: "tournament_prize_bundle"
        case .physical: "tournament_prize_physical"
        case .other: "tournament_prize_other"
        }
    }
}

extension TournamentGrantStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "tournament_grant_pending"
        case .granted: "tournament_grant_granted"
        case .fulfilled: "tournament_grant_fulfilled"
        case .failed: "tournament_grant_failed"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .pending: "tournament_grant_pending"
        case .granted: "tournament_grant_granted"
        case .fulfilled: "tournament_grant_fulfilled"
        case .failed: "tournament_grant_failed"
        }
    }
}

extension TournamentPrizeDistribution {
    var labelKey: LocalizedStringKey {
        switch self {
        case .perEntry: "tournament_distribution_per_entry"
        case .perMember: "tournament_distribution_per_member"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .perEntry: "tournament_distribution_per_entry"
        case .perMember: "tournament_distribution_per_member"
        }
    }
}

/** 队名，否则队员名字，否则短 id（Android `TournamentEntryLabel.displayName`，WEB `entryLabel`）。 */
func tournamentEntryName(_ label: TournamentEntryLabel?, fallback: String) -> String {
    guard let label else { return fallback }
    if let name = label.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
    let players = label.players.compactMap { $0.displayName?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return players.isEmpty ? "#\(label.id.prefix(6))" : players.joined(separator: " / ")
}

/** 每局比分 `21-18 19-21 21-15`。 */
func tournamentScoreLine(_ games: [TournamentGame]?) -> String {
    (games ?? []).map { "\($0.a)-\($0.b)" }.joined(separator: " ")
}

extension TournamentDivision {
    /** 这个组别现在能报名。 */
    func registrationOpen(now: Date = .now) -> Bool {
        guard status == .open else { return false }
        let opens = DateTimeFormatters.parseInstant(registrationOpensAt)
        let closes = DateTimeFormatters.parseInstant(registrationClosesAt)
        return (opens.map { now > $0 } ?? true) && (closes.map { now < $0 } ?? true)
    }

    /** 进候补之前还剩的名额。 */
    var placesLeft: Int { max(0, capacity - registeredCount - heldCount) }
}
