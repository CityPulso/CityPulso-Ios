import Foundation
import PulsoLinkCore

/** 一条订场在列表里显示的内容，不管哪个运动（Android `CourtBookingRowUi`）。 */
struct CourtBookingRowUi: Identifiable, Hashable, Sendable {
    let id: String
    let venueName: String
    let venueAddress: String
    let venueCoverImageId: String?
    let venueTimezone: String
    let startsAt: String
    let endsAt: String
    let status: CourtBookingStatus
    let expiresAt: String?
    let courtCount: Int
    let totalAmount: Double
    let currency: String
    /** 订到的场地名（去重）。 */
    let courtNames: [String]
}

extension CourtBookingRowUi {
    init(_ booking: BadmintonMyCourtBooking) {
        self.init(
            id: booking.id, venueName: booking.venueName, venueAddress: booking.venueAddress, venueCoverImageId: booking.venueCoverImageId,
            venueTimezone: booking.venueTimezone, startsAt: booking.startsAt, endsAt: booking.endsAt, status: booking.status,
            expiresAt: booking.expiresAt, courtCount: Set(booking.slots.map(\.courtId)).count, totalAmount: booking.totalAmount, currency: booking.currency,
            courtNames: booking.slots.map(\.courtName).filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        )
    }

    init(_ booking: TennisMyCourtBooking) {
        self.init(
            id: booking.id, venueName: booking.venueName, venueAddress: booking.venueAddress, venueCoverImageId: booking.venueCoverImageId,
            venueTimezone: booking.venueTimezone, startsAt: booking.startsAt, endsAt: booking.endsAt, status: booking.status,
            expiresAt: booking.expiresAt, courtCount: Set(booking.slots.map(\.courtId)).count, totalAmount: booking.totalAmount, currency: booking.currency,
            courtNames: booking.slots.map(\.courtName).filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        )
    }

    init(_ booking: PickleballMyCourtBooking) {
        self.init(
            id: booking.id, venueName: booking.venueName, venueAddress: booking.venueAddress, venueCoverImageId: booking.venueCoverImageId,
            venueTimezone: booking.venueTimezone, startsAt: booking.startsAt, endsAt: booking.endsAt, status: booking.status,
            expiresAt: booking.expiresAt, courtCount: Set(booking.slots.map(\.courtId)).count, totalAmount: booking.totalAmount, currency: booking.currency,
            courtNames: booking.slots.map(\.courtName).filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        )
    }
}

/** 球馆时间一律按球馆本地时区显示（Android `VenueTime.kt`、WEB `utils/venue/time.ts`），不跟设备时区。 */
enum VenueTime {
    static func zone(_ timezone: String) -> TimeZone {
        TimeZone(identifier: timezone) ?? .current
    }

    /** `EEE MMM d · HH:mm – HH:mm`。 */
    static func range(_ startsAt: String, _ endsAt: String, timezone: String, locale: Locale = .current) -> String {
        guard let start = DateTimeFormatters.parseInstant(startsAt), let end = DateTimeFormatters.parseInstant(endsAt) else { return "" }
        let zone = zone(timezone)
        return "\(format(start, "EEE MMM d · HH:mm", zone, locale)) – \(format(end, "HH:mm", zone, Locale(identifier: "en_US_POSIX")))"
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
