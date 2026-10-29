import Foundation
import Testing
@testable import PulsoLinkCore

struct FormattingTests {
    private let toronto = TimeZone(identifier: "America/Toronto")!

    @Test func sessionRanges() {
        let start = "2026-05-02T22:30:00Z"
        #expect(DateTimeFormatters.sessionTimeRange(start, "2026-05-03T00:00:00Z", timeZone: toronto) == "05/02 18:30 → 20:00")
        #expect(DateTimeFormatters.sessionTimeRange(start, "2026-05-03T05:00:00.000Z", timeZone: toronto) == "05/02 18:30 → 05/03 01:00")
        #expect(DateTimeFormatters.sessionDayClockRange(start, "2026-05-03T00:00:00Z", locale: Locale(identifier: "zh-Hans"), timeZone: toronto) == "5月2日 · 18:30 – 20:00")
        #expect(DateTimeFormatters.sessionDayClockRange(nil, start) == "")
    }

    @Test func calendarDateIgnoresLocalZone() {
        #expect(DateTimeFormatters.parseCalendarDate("1996-05-20T00:00:00Z") == DateComponents(year: 1996, month: 5, day: 20))
        #expect(DateTimeFormatters.parseCalendarDate("1996-05-20") == DateComponents(year: 1996, month: 5, day: 20))
        #expect(DateTimeFormatters.parseCalendarDate("nope") == nil)
    }

    @Test func haversineMatchesKnownDistance() {
        // Toronto City Hall → CN Tower ≈ 1.15 km
        let meters = haversineM(43.6534, -79.3841, 43.6426, -79.3871)
        #expect(abs(meters - 1_220) < 60)
    }

    @Test func money() {
        #expect(formatMoney(12.5, currency: "CAD", locale: Locale(identifier: "en_CA")) == "$12.50")
        #expect(formatCountdown(125) == "2:05")
        #expect(formatCountdown(-3) == "0:00")
    }
}
