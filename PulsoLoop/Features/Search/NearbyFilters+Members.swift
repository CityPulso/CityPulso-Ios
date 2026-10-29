import Foundation
import PulsoLinkCore

/* Android `NearbyFilters.kt` 里类体的成员。 */

extension EventNearbyFilters {
    /** 和默认值不同的筛选项数；排序不算。 */
    var activeCount: Int {
        [datePreset != .`any`, priceCap != .`any`, distance != .`any`, openSpotsOnly, includeEnded].filter { $0 }.count
    }

    /** 去掉距离（地图不用距离）的 [activeCount]。 */
    var mapActiveCount: Int {
        activeCount - (distance != .`any` ? 1 : 0)
    }

    /**
     * `[from, to)` 两个 RFC3339 时刻；ANY 时都是 nil。按本地日历日取整，一天之内查询 key 不变；一周到周日结束。
     */
    func startsAtRange(today: Date = .now, calendar: Calendar = .current) -> (String?, String?) {
        func dayStart(_ date: Date) -> String {
            DateTimeFormatters.rfc3339(calendar.startOfDay(for: date))
        }
        let start = calendar.startOfDay(for: today)
        switch datePreset {
        case .`any`:
            return (nil, nil)
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
