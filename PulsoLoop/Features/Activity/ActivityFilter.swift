/** 活动中心筛选（Android `ActivityFilter`）：先后顺序、看已结束还是未开始，「我参加的」下再分有名额 / 候补。 */
struct ActivityFilter: Hashable, Sendable {
    /** 最早的在前。 */
    var sortAsc = true
    /** 看已结束的活动（订场用 [bookings]）。 */
    var showEnded = false
    /** 「我的订场」下：即将开始还是已结束。 */
    var bookings = CourtBookingListTab.upcoming
    var joined: JoinedFilter = .participating

    /** 和默认值不同的项数，按钮上的角标。 */
    func activeCount(_ tab: ActivityCenterTab) -> Int {
        let defaults = ActivityFilter()
        return [sortAsc != defaults.sortAsc, tab != .courtBookings && showEnded != defaults.showEnded, tab == .joined && joined != defaults.joined, tab == .courtBookings && bookings != defaults.bookings]
            .filter { $0 }.count
    }
}
