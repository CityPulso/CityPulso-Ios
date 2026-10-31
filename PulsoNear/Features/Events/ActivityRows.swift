import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动卡片（对应 Android `ActivityFeedCard`）：封面上是「我发起 / 已报名」和活动类型，下面标题、日期、地点，
 * 底行名额、价格和状态。跟随 App 主题，不用活动类型色。
 */
struct ActivityFeedCard: View {
    let item: any ActivityItem
    /** 主持 / 已报名角标；nil 不显示（门店页的活动列表）。 */
    var badge: ActivityFeedBadge?
    let imageURL: URL?

    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActivityTypeCover(url: imageURL, activityType: item.activityType, iconSize: 56)
                .frame(height: 160)
                .clipped()
                .overlay(alignment: .top) {
                    HStack {
                        if let badge {
                            Label { Text(badge.labelKey) } icon: { Image(systemName: badge == .host ? "star" : "checkmark.circle") }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: palette.chipShape)
                        }
                        Spacer()
                        Label { Text(item.activityType.labelKey) } icon: { Image(item.activityType.iconAsset).resizable().frame(width: 14, height: 14) }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: palette.chipShape)
                    }
                    .padding(12)
                }
            VStack(alignment: .leading, spacing: 8) {
                ActivityTitle(title: item.title).font(.headline)
                ActivityMeta(systemImage: "calendar", text: timeLabel)
                if let venue = (item.venueName ?? item.address).flatMap({ $0.isEmpty ? nil : $0 }) {
                    ActivityMeta(systemImage: "mappin.and.ellipse", text: venue)
                }
                HStack(spacing: 8) {
                    if item.capacity > 0 {
                        Label { Text(verbatim: localizedFormat("activity_feed_capacity", item.capacity)) } icon: { Image(systemName: "person.2") }
                            .font(.footnote)
                    }
                    Spacer()
                    if !item.isEnded, let price = priceLabel {
                        price.font(.subheadline.weight(.semibold))
                    }
                    // 开放报名绿色、已结束灰色的柔和小标签（Android `ActivityStatusChip`）。
                    let tone = item.isEnded ? RadixScale.slate.lightStep(9) : RadixScale.green.lightStep(9)
                    Text(item.isEnded ? ActivityOpenStatus.ended.labelKey : ActivityOpenStatus.open.labelKey)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone)
                        .lineLimit(1)
                        .padding(.horizontal, PulsoSpace.s2)
                        .padding(.vertical, PulsoSpace.s1)
                        .background(tone.opacity(0.14), in: palette.chipShape)
                }
            }
            .padding()
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var timeLabel: String {
        let label = DateTimeFormatters.sessionDayClockRange(item.startsAt, item.endsAt, locale: locale)
        return label.isEmpty ? item.startsAt : label
    }

    private var priceLabel: Text? {
        if item.isFree { return Text("shell_calendar_badge_free") }
        return item.priceAmount.map { Text(verbatim: formatMoney($0, currency: item.currency.isEmpty ? "CAD" : item.currency, locale: locale)) }
    }
}

/**
 * 我的一条报名（对应 Android `<ActivityType>RegistrationListItem`）：封面、标题和状态 / 价格徽标、时间地点，
 * 下面活动类型和这个活动类型特有的标签。
 */
struct RegistrationRow: View {
    let item: any ActivityTypeRegistrationItem
    let imageURL: URL?
    var isHost = false

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                ActivityTypeCover(url: imageURL, activityType: item.activityType, iconSize: 32)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    ActivityTitle(title: item.title).font(.headline)
                    HStack(spacing: 6) {
                        if isHost { badge(Text("activity_detail_host_badge"), tint: .accentColor, solid: true) }
                        badge(statusLabel, tint: statusTint, solid: statusSolid)
                        if let price = priceLabel { badge(price, tint: item.isFree ? RegistrationTone.free : RegistrationTone.paid, solid: false) }
                    }
                    if item.registrationStatus == .pendingExit, !item.isEnded {
                        Text("shell_home_pending_exit_hint").font(.caption).foregroundStyle(.secondary)
                    }
                    ActivityMeta(systemImage: "calendar", text: timeLabel)
                    ActivityMeta(systemImage: "mappin.and.ellipse", text: venueLabel)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(Text(item.activityType.labelKey))
                    ForEach(item.optionLabels.indices, id: \.self) { chip(item.optionLabels[$0]) }
                    if item.isEnded { chip(Text("activity_detail_ended_badge")) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: Text {
        if item.isEnded { return Text("activity_detail_ended_badge") }
        return Text(item.registrationStatus.labelKey)
    }

    private var statusTint: Color {
        if item.isEnded || item.registrationStatus == .exited { return .secondary }
        return switch item.registrationStatus {
        case .waitlisted: RegistrationTone.waitlisted
        case .pendingExit: RegistrationTone.pendingExit
        case .awaitingPayment: RegistrationTone.awaitingPayment
        default: .accentColor
        }
    }

    private var statusSolid: Bool {
        (item.registrationStatus == .pendingExit || item.registrationStatus == .awaitingPayment) && !item.isEnded
    }

    private var priceLabel: Text? {
        if item.isFree { return Text("shell_calendar_badge_free") }
        return item.priceAmount.map { Text(verbatim: formatMoney($0, currency: item.currency.isEmpty ? "CAD" : item.currency, locale: locale)) }
    }

    private var timeLabel: String {
        let label = DateTimeFormatters.sessionDayClockRange(item.startsAt, item.endsAt, locale: locale)
        return label.isEmpty ? (item.startsAt.isEmpty ? "—" : item.startsAt) : label
    }

    private var venueLabel: String {
        [item.venueName, item.address].compactMap { $0 }.first { !$0.isEmpty } ?? "—"
    }

    private func badge(_ text: Text, tint: Color, solid: Bool) -> some View {
        text
            .font(.caption2.weight(.semibold))
            .foregroundStyle(solid ? Color.white : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(solid ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.15)), in: .capsule)
    }

    private func chip(_ text: Text) -> some View {
        text
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: .capsule)
    }
}

/** 报名状态与价签的文字色：Radix 第 11 阶，跟随深浅（Android `RegistrationTones`）。 */
enum RegistrationTone {
    static var waitlisted: Color { RadixScale.amber.step(11) }
    static var pendingExit: Color { RadixScale.orange.step(11) }
    static var awaitingPayment: Color { RadixScale.blue.step(11) }
    static var free: Color { RadixScale.green.step(11) }
    static var paid: Color { RadixScale.orange.step(11) }
}

/** 标题；空的显示「未命名活动」。 */
struct ActivityTitle: View {
    let title: String?

    var body: some View {
        Group {
            if let title, !title.isEmpty { Text(verbatim: title) } else { Text("explore_pin_untitled") }
        }
        .lineLimit(2)
    }
}

struct ActivityMeta: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: systemImage) }
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
