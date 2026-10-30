import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 混合了各运动的列表里的一场活动（对应 Android `HostedSessionRow`）。各运动保留自己的 DTO，
 * 列表项遵守这个协议（`Rows/<Sport>Rows.swift`）。
 */
protocol SportEventItem: Sendable {
    var sport: LoopSport { get }
    var id: String { get }
    var title: String? { get }
    var venueName: String? { get }
    var address: String? { get }
    var startsAt: String { get }
    var endsAt: String { get }
    var isEnded: Bool { get }
    var coverImageId: String? { get }
    var capacity: Int { get }
    var isFree: Bool { get }
    var priceAmount: Double? { get }
    var currency: String { get }
    /** 这个运动特有的字段做成的标签，按显示顺序（Android `<Sport>Options.labels()`）。 */
    var optionLabels: [Text] { get }
}

/** 我的一条报名（对应 Android `RegistrationRow`）。 */
protocol SportRegistrationItem: SportEventItem {
    var registrationId: String { get }
    var registrationStatus: RegistrationStatus { get }
    /** 主持这场活动的身份（和当前身份比较，标出自己主持的）。 */
    var profileId: String? { get }
}

/** 按开始时间排，同时间按 id；解析不了的排最后（Android `sortedByStartsAt`）。 */
func sortedByStartsAt<T>(_ rows: [T], startsAt: (T) -> String, id: (T) -> String, descending: Bool = false) -> [T] {
    rows.map { (DateTimeFormatters.parseInstant(startsAt($0)) ?? .distantFuture, $0) }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return descending ? lhs.0 > rhs.0 : lhs.0 < rhs.0 }
            return id(lhs.1) < id(rhs.1)
        }
        .map(\.1)
}

/** 已结束：接口说结束了，或结束时间已过。 */
func isEndedLike(isEnded: Bool, endsAt: String) -> Bool {
    isEnded || (DateTimeFormatters.parseInstant(endsAt).map { $0 < .now } ?? false)
}

/** 球拍类（羽毛球 / 网球 / 匹克球 / 乒乓球）的标签：赛制、组别、场地数 × 每场人数。 */
func racketOptionLabels(matchFormat: MatchFormat, eligibilityDivision: EligibilityDivision, courtCount: Int, playersPerCourt: Int) -> [Text] {
    var labels = [Text(matchFormat.labelKey), Text(eligibilityDivision.labelKey)]
    if courtCount > 0, playersPerCourt > 0 {
        labels.append(Text(verbatim: localizedFormat("shell_home_meta_courts", courtCount, playersPerCourt)))
    }
    return labels
}
