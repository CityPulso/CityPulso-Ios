import PulsoLinkUI
import SwiftUI

/* 会员闭集 → 文案（Android `features/membership/MembershipLabels.kt`）。 */

extension MembershipLedgerKind {
    var labelKey: LocalizedStringKey {
        switch self {
        case .purchase: "membership_kind_purchase"
        case .renew: "membership_kind_renew"
        case .upgrade: "membership_kind_upgrade"
        }
    }
}

extension MembershipStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .active: "membership_status_active"
        case .expired: "membership_status_expired"
        }
    }
}

extension MembershipLedgerStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "membership_ledger_status_pending"
        case .paid: "membership_ledger_status_paid"
        case .canceled: "membership_ledger_status_canceled"
        }
    }
}

extension MembershipChannel {
    var labelKey: LocalizedStringKey {
        switch self {
        case .platform: "membership_channel_platform"
        case .offline: "membership_channel_offline"
        }
    }
}

extension MembershipPaymentMethod {
    var titleKey: LocalizedStringKey {
        switch self {
        case .phone: "venue_payments_modes_phone_title"
        case .offline: "venue_payments_modes_offline_title"
        case .platform: "venue_payments_modes_platform_title"
        }
    }

    var bookerBodyKey: LocalizedStringKey {
        switch self {
        case .phone: "venue_membership_method_phone_body"
        case .offline: "venue_membership_method_offline_body"
        case .platform: "venue_membership_method_platform_body"
        }
    }
}

/** 时长档：月数为 nil 是终身。 */
func membershipTermLabel(_ months: Int?) -> String {
    months.map { localizedFormat("membership_months", $0) } ?? String(localized: "membership_lifetime")
}

/** 中文「N 折」的数字：会员付原价的份额 ÷ 10（减 10% → "9"，减 3% → "97"，减 15% → "85"，减 95% → "0.5"）。 */
func bookingDiscountZhe(_ percentOff: Int) -> String {
    let paid = 100 - percentOff
    if paid >= 10, paid % 10 != 0 { return String(paid) }
    if paid % 10 == 0 { return String(paid / 10) }
    return String(Double(paid) / 10)
}

extension MembershipLevelIconPreset {
    var systemImage: String {
        switch self {
        case .medal: "medal"
        case .trophy: "trophy"
        case .award: "rosette"
        case .gem: "diamond"
        case .star: "star"
        case .sparkles: "sparkles"
        case .rocket: "airplane.departure"
        case .zap: "bolt"
        case .flame: "flame"
        case .leaf: "leaf"
        case .shield: "shield"
        case .badgeCheck: "checkmark.seal"
        case .calendarCheck: "calendar.badge.checkmark"
        case .heart: "heart"
        case .users: "person.3"
        case .graduationCap: "graduationcap"
        }
    }
}

extension MembershipLevelColorPreset {
    /** 卡面渐变：左上亮 → 右下暗，和 WEB `--level-from/via/to` 同序。 */
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(argb: from), Color(argb: via), Color(argb: to)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var inkColor: Color { Color(argb: ink) }
}

extension Color {
    /** `0xAARRGGBB`（Android Compose `Color(Long)`）。 */
    init(argb: Int64) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}

/** 会员等级圆章：等级主色渐变 + 图标（Android `MembershipLevelBadge`，WEB `LevelIcon`）。 */
struct MembershipLevelBadge: View {
    let icon: String
    let color: String
    var size: CGFloat = 28

    var body: some View {
        let theme = MembershipLevelColorPreset.fromWire(color)
        Image(systemName: MembershipLevelIconPreset.fromWire(icon).systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(theme.inkColor)
            .frame(width: size, height: size)
            .background(theme.gradient, in: .circle)
    }
}
