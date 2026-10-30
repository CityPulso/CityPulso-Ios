import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动卡片（对应 Android `EventFeedCard`）：封面上是「我发起 / 已报名」和运动，下面标题、日期、地点，
 * 底行名额、价格和状态。跟随 App 主题，不用运动色。
 */
struct EventFeedCard: View {
    let item: any SportEventItem
    /** 主持 / 已报名角标；nil 不显示（球馆页的活动列表）。 */
    var badge: EventFeedBadge?
    let imageURL: URL?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SportCover(url: imageURL, sport: item.sport, iconSize: 56)
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
                                .background(Color.accentColor, in: .capsule)
                        }
                        Spacer()
                        Label { Text(item.sport.labelKey) } icon: { Image(item.sport.iconAsset).resizable().frame(width: 14, height: 14) }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .padding(12)
                }
            VStack(alignment: .leading, spacing: 8) {
                EventTitle(title: item.title).font(.headline)
                EventMeta(systemImage: "calendar", text: timeLabel)
                if let venue = (item.venueName ?? item.address).flatMap({ $0.isEmpty ? nil : $0 }) {
                    EventMeta(systemImage: "mappin.and.ellipse", text: venue)
                }
                HStack(spacing: 8) {
                    if item.capacity > 0 {
                        Label { Text(verbatim: localizedFormat("event_feed_capacity", item.capacity)) } icon: { Image(systemName: "person.2") }
                            .font(.footnote)
                    }
                    Spacer()
                    if !item.isEnded, let price = priceLabel {
                        price.font(.subheadline.weight(.semibold))
                    }
                    Text(item.isEnded ? EventOpenStatus.ended.labelKey : EventOpenStatus.open.labelKey)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: .capsule)
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
 * 我的一条报名（对应 Android `<Sport>RegistrationListItem`）：封面、标题和状态 / 价格徽标、时间地点，
 * 下面运动和这个运动特有的标签。
 */
struct RegistrationRow: View {
    let item: any SportRegistrationItem
    let imageURL: URL?
    var isHost = false

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                SportCover(url: imageURL, sport: item.sport, iconSize: 32)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    EventTitle(title: item.title).font(.headline)
                    HStack(spacing: 6) {
                        if isHost { badge(Text("event_detail_host_badge"), tint: .accentColor, solid: true) }
                        badge(statusLabel, tint: statusTint, solid: statusSolid)
                        if let price = priceLabel { badge(price, tint: item.isFree ? RegistrationTone.free : RegistrationTone.paid, solid: false) }
                    }
                    if item.registrationStatus == .pendingExit, !item.isEnded {
                        Text("shell_home_pending_exit_hint").font(.caption).foregroundStyle(.secondary)
                    }
                    EventMeta(systemImage: "calendar", text: timeLabel)
                    EventMeta(systemImage: "mappin.and.ellipse", text: venueLabel)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(Text(item.sport.labelKey))
                    ForEach(item.optionLabels.indices, id: \.self) { chip(item.optionLabels[$0]) }
                    if item.isEnded { chip(Text("event_detail_ended_badge")) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: Text {
        if item.isEnded { return Text("event_detail_ended_badge") }
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

/** 一条订场（对应 Android `CourtBookingRowItem`）：球馆、状态、球馆时区的时间、地址、场地数、金额，待付款时倒计时。 */
struct CourtBookingRow: View {
    let booking: CourtBookingRowUi
    let coverURL: URL?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                if let coverURL { PulsoRemoteImage(url: coverURL) } else { Image(systemName: "building.2").foregroundStyle(.secondary) }
            }
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: booking.venueName).font(.headline).lineLimit(1)
                    Spacer()
                    Text(booking.status.labelKey)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(booking.status.tone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(booking.status.tone.opacity(0.15), in: .capsule)
                }
                Text(verbatim: VenueTime.range(booking.startsAt, booking.endsAt, timezone: booking.venueTimezone, locale: locale))
                    .font(.footnote)
                EventMeta(systemImage: "mappin", text: booking.venueAddress)
                HStack(spacing: 8) {
                    Text(verbatim: localizedFormat("court_bookings_courts", booking.courtCount))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: .capsule)
                    Text(verbatim: formatMoney(booking.totalAmount, currency: booking.currency, locale: locale))
                        .font(.subheadline.weight(.semibold))
                    if let holdUntil, holdUntil > .now {
                        Text(timerInterval: Date.now...holdUntil, countsDown: true)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(RadixScale.amber.step(11))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var holdUntil: Date? {
        guard booking.status == .pending || booking.status == .awaitingPayment else { return nil }
        return DateTimeFormatters.parseInstant(booking.expiresAt)
    }
}

extension CourtBookingStatus {
    /** 状态色（Android `CourtBookingStatus.tone()`）。 */
    var tone: Color {
        switch self {
        case .pending, .awaitingApproval: RadixScale.amber.step(11)
        case .awaitingPayment: RadixScale.blue.step(11)
        case .confirmed: RadixScale.green.step(11)
        case .canceled, .expired: .secondary
        }
    }
}

/** 标题；空的显示「未命名活动」。 */
struct EventTitle: View {
    let title: String?

    var body: some View {
        Group {
            if let title, !title.isEmpty { Text(verbatim: title) } else { Text("explore_pin_untitled") }
        }
        .lineLimit(2)
    }
}

struct EventMeta: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: systemImage) }
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
