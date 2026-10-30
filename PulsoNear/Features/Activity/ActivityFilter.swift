/** 活动中心筛选（Android `ActivityFilter`）：先后顺序、看已结束还是未开始，「我参加的」下再分有名额 / 候补。 */
struct ActivityFilter: Hashable, Sendable {
    /** 最早的在前。 */
    var sortAsc = true
    /** 看已结束的（订场有自己的即将开始 / 已结束分段）。 */
    var showEnded = false
    var joined: JoinedFilter = .participating

    /** 和默认值不同的项数，按钮上的角标。 */
    func activeCount(_ tab: ActivityCenterTab) -> Int {
        let defaults = ActivityFilter()
        return [sortAsc != defaults.sortAsc, tab != .spaceBookings && showEnded != defaults.showEnded, tab == .joined && joined != defaults.joined]
            .filter { $0 }.count
    }
}
