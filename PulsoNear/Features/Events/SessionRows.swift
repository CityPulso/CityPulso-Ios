import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 混合了各种活动的列表里的一场活动（对应 Android `HostedSessionRow`）。各活动类型保留自己的 DTO，
 * 列表项遵守这个协议（`Rows/<ActivityType>Rows.swift`）。
 */
protocol ActivityItem: Sendable {
    var activityType: NearActivityKind { get }
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
    /** 这种活动特有的字段做成的标签，按显示顺序（Android `<ActivityType>Options.labels()`）。 */
    var optionLabels: [Text] { get }
}

/** 我的一条报名（对应 Android `RegistrationRow`）。 */
protocol ActivityTypeRegistrationItem: ActivityItem {
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

/** 「6 人」或「4–8 人」（Android `participantsLabel`，WEB `participantsExact` / `participantsRange`）。 */
func participantsLabel(minParticipants: Int, capacity: Int) -> String {
    minParticipants == capacity
        ? localizedFormat("activity_detail_participants_exact", capacity)
        : localizedFormat("activity_detail_participants_range", minParticipants, capacity)
}
