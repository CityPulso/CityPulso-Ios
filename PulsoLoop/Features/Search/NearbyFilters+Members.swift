import Foundation
import PulsoLinkCore

/* Android `NearbyFilters.kt` 里类体的成员。 */

extension EventNearbyFilters {
    /** 「即将开始」的起点按几分钟取整。 */
    static let upcomingStepMinutes = 5

    /** 和默认值不同的筛选项数；排序不算。 */
    var activeCount: Int {
        [datePreset != .upcoming, priceCap != .`any`, distance != .`any`, openSpotsOnly, includeEnded].filter { $0 }.count
    }

    /** 去掉距离（地图不用距离）的 [activeCount]。 */
    var mapActiveCount: Int {
        activeCount - (distance != .`any` ? 1 : 0)
    }

    /**
     * `[from, to)` 两个 RFC3339 时刻。「即将开始」从现在起、没有结束，向下取整到 [upcomingStepMinutes]，一段时间内查询 key 不变；
     * 按天的选项按本地日历日取整；一周到周日结束。
     */
    func startsAtRange(today: Date = .now, calendar: Calendar = .current) -> (String?, String?) {
        func dayStart(_ date: Date) -> String {
            DateTimeFormatters.rfc3339(calendar.startOfDay(for: date))
        }
        let start = calendar.startOfDay(for: today)
        switch datePreset {
        case .upcoming:
            let minute = Int(today.timeIntervalSince1970) / 60
            return (DateTimeFormatters.rfc3339(Date(timeIntervalSince1970: TimeInterval((minute - minute % Self.upcomingStepMinutes) * 60))), nil)
        case .today:
            return (dayStart(start), dayStart(calendar.date(byAdding: .day, value: 1, to: start)!))
        case .thisWeek:
            // 下一个（或今天就是的）周日，再加一天。
            let weekday = calendar.component(.weekday, from: start) // 1 = Sunday
            let toSunday = (8 - weekday) % 7
            return (dayStart(start), dayStart(calendar.date(byAdding: .day, value: toSunday + 1, to: start)!))
        case .thisMonth:
            let month = calendar.dateInterval(of: .month, for: start)!
            return (dayStart(start), dayStart(month.end))
        case .custom:
            return (customFrom.isEmpty ? nil : customFrom, customTo.isEmpty ? nil : customTo)
        }
    }
}

extension VenueNearbyFilters {
    var activeCount: Int {
        [distance != .`any`, hourlyCap != .`any`, !amenities.isEmpty, !openNow, acceptsMembership, acceptsPlatform].filter { $0 }.count
    }

    var mapActiveCount: Int {
        activeCount - (distance != .`any` ? 1 : 0)
    }

    /** 给接口的设施图标 key，按预设顺序。 */
    var amenityIcons: [String] {
        VenueAmenityPreset.allCases.filter(amenities.contains).map(\.icon)
    }
}

extension NearbyDistance {
    var radiusM: Int? {
        km.map { $0 * 1000 }
    }
}
