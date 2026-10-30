import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一条预约（对应 Android `SpaceBookingRowItem`）：门店、状态、门店时区的时间、地址、桌台数、金额，待付款时倒计时。 */
struct SpaceBookingRow: View {
    let booking: SpaceBookingRowUi
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
                ActivityMeta(systemImage: "mappin", text: booking.venueAddress)
                HStack(spacing: 8) {
                    Text(verbatim: localizedFormat("space_bookings_spaces", booking.spaceCount))
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

extension SpaceBookingStatus {
    /** 状态色（Android `SpaceBookingStatus.tone()`）。 */
    var tone: Color {
        switch self {
        case .pending: RadixScale.amber.step(11)
        case .awaitingPayment: RadixScale.blue.step(11)
        case .confirmed: RadixScale.green.step(11)
        case .canceled, .expired: .secondary
        }
    }
}

