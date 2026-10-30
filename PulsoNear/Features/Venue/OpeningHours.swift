import Foundation

/** 一天的营业时段（"HH:mm"）；nil = 休息。 */
struct DayHours: Hashable, Sendable {
    let opensAt: String
    let closesAt: String
}

/** [fromDay]…[toDay]（ISO，周一 = 1）营业时间相同的几天。 */
struct WeekHoursRun: Hashable, Sendable {
    var fromDay: Int
    var toDay: Int
    var hours: DayHours?
}

enum VenueOpenStatus: Hashable, Sendable {
    case open(closesAt: String)
    /** 现在没开；[inDays] 天后（0 = 今天晚些）在 ISO 的 [dayOfWeek] 的 [opensAt] 开门。 */
    case closed(opensAt: String, inDays: Int, dayOfWeek: Int)
}

/** 周一在前的一周营业时段（Android `venueWeek`，WEB `venueWeek`）。 */
func venueWeek(_ hours: [VenueDayHours]) -> [DayHours?] {
    (1 ... 7).map { day in hours.first { $0.dayOfWeek == day }.map { DayHours(opensAt: $0.opensAt, closesAt: $0.closesAt) } }
}

/** 把一周合并成营业时间相同的几段，周一在前（WEB `groupWeekHours`）。 */
func groupWeekHours(_ week: [DayHours?]) -> [WeekHoursRun] {
    var runs: [WeekHoursRun] = []
    for (index, hours) in week.enumerated() {
        let day = index + 1
        if let last = runs.last, last.hours == hours {
            runs[runs.count - 1].toDay = day
        } else {
            runs.append(WeekHoursRun(fromDay: day, toDay: day, hours: hours))
        }
    }
    return runs
}

/** 现在开着、开到几点，或者一周内下一次开门；门店没填营业时间时 nil（WEB `venueOpenStatus`）。 */
func venueOpenStatus(_ week: [DayHours?], timezone: String, now: Date = .now) -> VenueOpenStatus? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .current
    let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
    // Calendar 周日 = 1；换成 ISO 周一 = 1。
    let isoDay = ((parts.weekday ?? 1) + 5) % 7 + 1
    let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    if let today = week[isoDay - 1] {
        if minutes >= clockMinutes(today.opensAt), minutes < clockMinutes(today.closesAt) { return .open(closesAt: today.closesAt) }
        if minutes < clockMinutes(today.opensAt) { return .closed(opensAt: today.opensAt, inDays: 0, dayOfWeek: isoDay) }
    }
    for inDays in 1 ... 7 {
        let dayOfWeek = (isoDay - 1 + inDays) % 7 + 1
        guard let next = week[dayOfWeek - 1] else { continue }
        return .closed(opensAt: next.opensAt, inDays: inDays, dayOfWeek: dayOfWeek)
    }
    return nil
}

private func clockMinutes(_ clock: String) -> Int {
    let parts = clock.split(separator: ":").map { Int($0) ?? 0 } + [0, 0]
    return parts[0] * 60 + parts[1]
}

extension [ActivityTypeEntrySummary] {
    /** 各活动类型入口里最低的每小时价格。 */
    var lowestHourlyPrice: Double? {
        compactMap(\.minHourlyPriceAmount).min()
    }
}

extension NearbyVenuePin {
    var displayName: String { building.name }
    var displayAddress: String { building.address }
}
