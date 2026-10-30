import Foundation
import PulsoLinkCore

/** 一条订场在列表里显示的内容，不管哪个运动（Android `CourtBookingRowUi`）。 */
struct CourtBookingRowUi: Identifiable, Hashable, Sendable, Codable {
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

    /** 从球馆本地今天起 [days] 天的 "yyyy-MM-dd"。 */
    static func dateKeys(timezone: String, days: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone(timezone)
        let today = calendar.startOfDay(for: .now)
        return (0 ..< max(days, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { format($0, "yyyy-MM-dd", calendar.timeZone, Locale(identifier: "en_US_POSIX")) }
        }
    }

    /** "yyyy-MM-dd" → 那一天的正午（只用来按日期格式化，key 已是球馆本地日期）。 */
    static func date(fromKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: key + " 12:00")
    }

    /** "yyyy-MM-dd" → 短星期 + 日期。 */
    static func dateKeyLabel(_ key: String, locale: Locale = .current) -> String {
        guard let date = date(fromKey: key) else { return key }
        return format(date, "EEE d MMM", TimeZone(identifier: "UTC")!, locale)
    }

    /** "yyyy-MM-dd" → 星期几、月日两行（订场日期条）。 */
    static func dateKeyParts(_ key: String, locale: Locale = .current) -> (weekday: String, day: String) {
        guard let date = date(fromKey: key) else { return ("", key) }
        let utc = TimeZone(identifier: "UTC")!
        return (format(date, "EEE", utc, locale), format(date, "MMM d", utc, locale))
    }

    /** 球馆本地 `HH:mm`。 */
    static func clock(_ iso: String, timezone: String) -> String {
        DateTimeFormatters.parseInstant(iso).map { format($0, "HH:mm", zone(timezone), Locale(identifier: "en_US_POSIX")) } ?? ""
    }

    /** 球馆本地 `EEE MMM d · HH:mm`。 */
    static func dateTime(_ iso: String, timezone: String, locale: Locale = .current) -> String {
        DateTimeFormatters.parseInstant(iso).map { format($0, "EEE MMM d · HH:mm", zone(timezone), locale) } ?? ""
    }

    /** 球馆本地日期（会员有效期这类只关心哪天的时间点）。 */
    static func date(_ iso: String, timezone: String, locale: Locale = .current) -> String {
        guard let date = DateTimeFormatters.parseInstant(iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone(timezone)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /** 离 [iso] 还有几天（向上取整，过了是 0）；解析不了 nil。 */
    static func daysUntil(_ iso: String, now: Date = .now) -> Int? {
        guard let date = DateTimeFormatters.parseInstant(iso) else { return nil }
        return max(0, Int((date.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
