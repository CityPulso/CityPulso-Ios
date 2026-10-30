import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* 时长包闭集 → 文案 / 颜色（Android `features/bundle/BundleLabels.kt`，文案来自 WEB `features.bundle`）。 */

extension BundleState {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "bundle_state_pending"
        case .active: "bundle_state_active"
        case .usedUp: "bundle_state_used_up"
        case .expired: "bundle_state_expired"
        case .canceled: "bundle_state_canceled"
        }
    }

    var tone: Color {
        switch self {
        case .pending: RadixScale.amber.lightStep(9)
        case .active: RadixScale.green.lightStep(9)
        case .usedUp, .expired, .canceled: RadixScale.slate.lightStep(9)
        }
    }
}

extension BundleLedgerKind {
    var labelKey: LocalizedStringKey {
        switch self {
        case .purchase: "bundle_ledger_kind_purchase"
        case .bookingUsage: "bundle_ledger_kind_booking_usage"
        case .bookingRestore: "bundle_ledger_kind_booking_restore"
        case .adjustment: "bundle_ledger_kind_adjustment"
        }
    }

    var tone: Color {
        switch self {
        case .purchase: RadixScale.green.lightStep(9)
        case .bookingUsage, .bookingRestore: RadixScale.blue.lightStep(9)
        case .adjustment: RadixScale.amber.lightStep(9)
        }
    }
}

extension BundlePaymentMethod {
    /** 短方式名（详情页「付款方式」一行）。 */
    var labelKey: LocalizedStringKey {
        switch self {
        case .phone: "bundle_method_phone"
        case .offline: "bundle_method_offline"
        case .platform: "bundle_method_platform"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .phone: "bundle_method_phone_title"
        case .offline: "bundle_method_offline_title"
        case .platform: "bundle_method_platform_title"
        }
    }

    var bookerBodyKey: LocalizedStringKey {
        switch self {
        case .phone: "bundle_method_phone_body"
        case .offline: "bundle_method_offline_body"
        case .platform: "bundle_method_platform_body"
        }
    }
}

/** 有效期：N 天，或永不过期。 */
func bundleValidityLabel(_ validDays: Int?) -> String {
    validDays.map { localizedFormat("bundle_offer_valid_days", $0) } ?? String(localized: "bundle_offer_never_expires")
}

/**
 * 一张在售时长包的票（Android `BundleOfferTicket`）：时长、价格、每小时多少、比按场地付省多少、会员价起、有效期。
 */
struct BundleOfferTicket: View {
    let offer: BundleOffer
    let hourlyPrice: Double?
    var selected = false
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let saving = bundleSavingPercent(offer.priceAmount, includedMinutes: offer.includedMinutes, hourlyPrice: hourlyPrice)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("bundle_ticket_eyebrow").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let saving {
                        VenueChip(text: localizedFormat("bundle_offer_saving", saving), tone: RadixScale.green.lightStep(9))
                    }
                }
                Text(verbatim: offer.name).font(.headline).lineLimit(2)
                Text(verbatim: formatBundleHours(offer.includedMinutes, locale: locale)).font(.title2.bold().monospacedDigit())
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("bundle_ticket_price").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: formatMoney(offer.priceAmount, currency: offer.currency, locale: locale)).font(.subheadline.bold().monospacedDigit())
                }
                Text(verbatim: localizedFormat("bundle_offer_per_hour", formatMoney(bundleHourlyAmount(offer.priceAmount, includedMinutes: offer.includedMinutes), currency: offer.currency, locale: locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let member = offer.lowestMemberPrice {
                    Text(verbatim: localizedFormat("bundle_offer_member_from", member.levelName, formatMoney(member.priceAmount, currency: offer.currency, locale: locale)))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Text(verbatim: bundleValidityLabel(offer.validDays)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 220, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 2 : 0.5))
        }
        .buttonStyle(.plain)
    }
}

/** 一张已买的时长包（Android `BundleTicket`）：名字、球馆、剩余 / 总时长、余量条、状态、到期。 */
struct BundleTicket: View {
    let item: any BundleHolding
    let coverURL: URL?

    @Environment(\.locale) private var locale

    var body: some View {
        let state = item.state()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SportCover(url: coverURL, sport: item.sports.first?.loopSport ?? .badminton, iconSize: 20)
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name).font(.headline).lineLimit(1)
                    Text(verbatim: item.venueName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VenueChip(text: String(localized: state.labelResource), tone: state.tone)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: formatBundleHourCount(item.remainingMinutes, locale: locale)).font(.title3.bold().monospacedDigit())
                Text(verbatim: localizedFormat("bundle_ticket_remaining", formatBundleHours(item.includedMinutes, locale: locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: item.balanceShare).tint(state.tone)
            Group {
                if let expiresAt = item.expiresAt {
                    Text(verbatim: localizedFormat(state == .expired ? "bundle_ticket_ended" : "bundle_ticket_expires", VenueTime.date(expiresAt, timezone: item.venueTimezone, locale: locale)))
                } else {
                    Text(verbatim: bundleValidityLabel(item.validDays))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

extension BundleState {
    var labelResource: String.LocalizationValue {
        switch self {
        case .pending: "bundle_state_pending"
        case .active: "bundle_state_active"
        case .usedUp: "bundle_state_used_up"
        case .expired: "bundle_state_expired"
        case .canceled: "bundle_state_canceled"
        }
    }
}
