import Foundation

/**
 * 时间格式（对应 Android `DateTimeFormatters`、PulsoLink-Package `utils/primitive/time`）。
 * 输入是接口的 RFC3339 / ISO 字符串；输出按 [locale] 与 [timeZone] 显示。
 */
public enum DateTimeFormatters {
    /** RFC3339 时刻，带不带毫秒都能读；读不了返回 nil。 */
    public static func parseInstant(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    /** 日历日（生日等）：纯 `YYYY-MM-DD` 原样取日；带 `T` 的取 UTC 那一天，不做本地换日。 */
    public static func parseCalendarDate(_ raw: String?) -> DateComponents? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        if raw.contains("T") {
            return parseInstant(raw).map { utc.dateComponents([.year, .month, .day], from: $0) }
        }
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    /** `HH:mm`。 */
    public static func clockTime(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        parseInstant(iso).map { format($0, "HH:mm", locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone) }
    }

    /** 地图针 / 场次短格式 `MM/dd HH:mm`。 */
    public static func pinMonthDayTime(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        parseInstant(iso).map { format($0, "MM/dd HH:mm", locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone) }
    }

    /** 本地化中等日期 + 短时间。 */
    public static func monthDayTime(_ iso: String?, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let date = parseInstant(iso) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /** 同日 `MM/dd HH:mm → HH:mm`，跨日两端都带月日（Package `formatSessionTimeRange`）。 */
    public static func sessionTimeRange(_ startsAt: String?, _ endsAt: String?, timeZone: TimeZone = .current) -> String {
        guard let start = parseInstant(startsAt), let end = parseInstant(endsAt) else {
            return [pinMonthDayTime(startsAt, timeZone: timeZone), pinMonthDayTime(endsAt, timeZone: timeZone)]
                .compactMap { $0 }.joined(separator: " → ")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let posix = Locale(identifier: "en_US_POSIX")
        let endLabel = calendar.isDate(start, inSameDayAs: end)
            ? format(end, "HH:mm", locale: posix, timeZone: timeZone)
            : format(end, "MM/dd HH:mm", locale: posix, timeZone: timeZone)
        return "\(format(start, "MM/dd HH:mm", locale: posix, timeZone: timeZone)) → \(endLabel)"
    }

    /** 场次列表行 `d MMM · HH:mm – HH:mm`（中文 `M月d日`），月份跟 App 语言。 */
    public static func sessionDayClockRange(_ startsAt: String?, _ endsAt: String?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let start = parseInstant(startsAt), let end = parseInstant(endsAt) else { return "" }
        let day = locale.language.languageCode?.identifier == "zh"
            ? format(start, "M月d日", locale: locale, timeZone: timeZone)
            : format(start, "d MMM", locale: locale, timeZone: timeZone)
        let posix = Locale(identifier: "en_US_POSIX")
        return "\(day) · \(format(start, "HH:mm", locale: posix, timeZone: timeZone)) – \(format(end, "HH:mm", locale: posix, timeZone: timeZone))"
    }

    /** RFC3339（UTC，带毫秒），和 Android `Instant.toString()` 一样给接口用。 */
    public static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func format(_ date: Date, _ pattern: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
