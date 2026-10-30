import Foundation
import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动中心（日历和资料页共用，对应 Android `ActivityCenterViewModel`）：先选运动，再选我发起的 / 我参加的 / 我的订场，
 * 筛选里调先后、已结束和「已有名额 / 候补」。每个运动读自己的 Service（报名会让它们失效）。
 */
@MainActor
@Observable
final class ActivityCenterModel {
    /** 和 WEB 一样：每种最多最新的 100 条，含已结束的。 */
    private static let pageSize = 100
    private static let seatStatuses: Set<RegistrationStatus> = [.participating, .pendingExit, .awaitingPayment]

    var sport: LoopSport = .badminton { didSet { if sport != oldValue { reloadEvents(); reloadBookings() } } }
    var tab: ActivityCenterTab
    var filter = ActivityFilter() { didSet { if filter.bookings != oldValue.bookings { reloadBookings() } } }
    private(set) var isPulser = false
    private(set) var loading = false
    private(set) var error: UiError?
    private(set) var hosted: [any SportEventItem] = []
    private(set) var joined: [any SportRegistrationItem] = []
    private(set) var bookings = Loadable<[CourtBookingRowUi]>()

    @ObservationIgnored @Injected(\.loopSportServices) private var services
    @ObservationIgnored @Injected(\.venueSportServices) private var venueServices
    @ObservationIgnored @Injected(\.venueEventBus) private var venueEventBus
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var hostedAnswer: QueryResponse<[any SportEventItem]> = .loading
    @ObservationIgnored private var joinedAnswer: QueryResponse<[any SportRegistrationItem]> = .loading
    @ObservationIgnored private var bookingsTask: Task<Void, Never>?

    /** [initialTab]：从订场页「我的订场」进来时直接停在订场。 */
    init(initialTab: ActivityCenterTab = .hosted) {
        tab = initialTab
    }

    /** 要发起活动得有 pulser 角色；所有人都能看自己参加的和订场。 */
    /**
     * 在第二层标签之间滑动；滑过最后（第一）个就到下一个（上一个）运动的第一个（最后一个）标签。
     * 还没开放的运动只算一页。
     */
    func swipe(forward: Bool) {
        let index = tabs.firstIndex(of: tab) ?? 0
        let all = LoopSport.allCases
        let current = all.firstIndex(of: sport) ?? 0
        let atStart = !sport.available || index <= 0
        let atEnd = !sport.available || index >= tabs.count - 1
        if forward, !atEnd {
            tab = tabs[index + 1]
        } else if !forward, !atStart {
            tab = tabs[index - 1]
        } else if forward, current < all.count - 1 {
            sport = all[current + 1]
            tab = tabs.first ?? tab
        } else if !forward, current > 0 {
            sport = all[current - 1]
            tab = tabs.last ?? tab
        }
    }

    var tabs: [ActivityCenterTab] {
        isPulser ? ActivityCenterTab.allCases : [.joined, .courtBookings]
    }

    /** 这个运动能订场时对应的场馆运动。 */
    var venueSport: VenueSport? {
        VenueSport.allCases.first { $0.loopSport == sport }
    }

    var hostedItems: [any SportEventItem] {
        sortedByStartsAt(
            hosted.filter { filter.showEnded == isEndedLike(isEnded: $0.isEnded, endsAt: $0.endsAt) },
            startsAt: \.startsAt, id: \.id, descending: !filter.sortAsc
        )
    }

    var joinedItems: [any SportRegistrationItem] {
        let rows = joined.filter { row in
            let inGroup = switch filter.joined {
            case .participating: Self.seatStatuses.contains(row.registrationStatus)
            case .waitlisted: row.registrationStatus == .waitlisted
            }
            return inGroup && filter.showEnded == isEndedLike(isEnded: row.isEnded, endsAt: row.endsAt)
        }
        return sortedByStartsAt(rows, startsAt: \.startsAt, id: \.id, descending: !filter.sortAsc)
    }

    var bookingItems: [CourtBookingRowUi] {
        sortedByStartsAt(bookings.data ?? [], startsAt: \.startsAt, id: \.id, descending: !filter.sortAsc)
    }

    var isLoadingList: Bool {
        tab == .courtBookings ? bookings.isLoading && bookings.data == nil : loading && hosted.isEmpty && joined.isEmpty
    }

    var listError: UiError? {
        tab == .courtBookings ? bookings.error : error
    }

    var isListEmpty: Bool {
        switch tab {
        case .hosted: hostedItems.isEmpty
        case .joined: joinedItems.isEmpty
        case .courtBookings: bookingItems.isEmpty
        }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /** 跟着当前身份；页面消失时随 `.task` 取消。 */
    func observe() async {
        for await info in profileStore.current.values() {
            isPulser = info?.isPulser == true
            if !isPulser, tab == .hosted { tab = .joined }
            reloadEvents()
            reloadBookings()
        }
        eventsTask?.cancel()
        bookingsTask?.cancel()
    }

    /** 下拉刷新：重拉这个运动的活动、报名和订场。 */
    func refresh() async {
        guard let scope = scope() else { return }
        venueEventBus.invalidate()
        // 失败由上面订阅的 stream 报出来。
        guard let service = services[sport] else { return }
        try? await service.freshHostedEvents(accountId: scope.accountId, profileId: scope.profileId, hostedProfileId: scope.hostedId, limit: Self.pageSize)
        try? await service.freshMyRegistrations(Self.joinedQuery(scope))
    }

    /** 我参加的：含已结束，不含我主持的（它们在「我发起的」里）。 */
    private static func joinedQuery(_ scope: (accountId: String, profileId: String, hostedId: String)) -> SportRegistrationsQuery {
        SportRegistrationsQuery(accountId: scope.accountId, profileId: scope.profileId, limit: pageSize, includeEnded: true, excludeHosted: true)
    }

    private func scope() -> (accountId: String, profileId: String, hostedId: String)? {
        let session = sessionStore.state.value
        let shown = profileStore.current.value?.profileId
        let hostedId = shown?.isEmpty == false ? shown! : session.currentProfileId
        guard !session.currentAccountId.isEmpty, !hostedId.isEmpty else { return nil }
        return (session.currentAccountId, session.currentProfileId, hostedId)
    }

    private func reloadEvents() {
        eventsTask?.cancel()
        hosted = []
        joined = []
        error = nil
        guard let scope = scope(), let service = services[sport] else {
            loading = false
            return
        }
        loading = true
        let hostedStream = service.hostedEvents(accountId: scope.accountId, profileId: scope.profileId, hostedProfileId: scope.hostedId, limit: Self.pageSize)
        let joinedStream = service.myRegistrations(Self.joinedQuery(scope))
        hostedAnswer = .loading
        joinedAnswer = .loading
        eventsTask = Task {
            await concurrently([
                {
                    for await response in hostedStream {
                        self.hostedAnswer = response
                        self.apply()
                    }
                },
                {
                    for await response in joinedStream {
                        self.joinedAnswer = response
                        self.apply()
                    }
                },
            ])
        }
    }

    /** 两边都回来才换列表；任一边出错就显示错误（Android `applyResponses`）。 */
    private func apply() {
        switch (hostedAnswer, joinedAnswer) {
        case let (.error(failure), _), let (_, .error(failure)):
            loading = false
            error = failure
        case let (.data(hostedRows), .data(joinedRows)):
            loading = false
            error = nil
            hosted = hostedRows
            joined = joinedRows
        default:
            loading = hosted.isEmpty && joined.isEmpty
            error = nil
        }
    }

    private func reloadBookings() {
        bookingsTask?.cancel()
        bookings = Loadable()
        guard let scope = scope(), let venueSport else { return }
        let stream = venueServices[venueSport]!.myBookings(
            MyCourtBookingsKey(accountId: scope.accountId, profileId: scope.profileId, upcoming: filter.bookings == .upcoming, limit: Self.pageSize)
        )
        bookingsTask = Task {
            for await response in stream {
                bookings = bookings.reduce(response)
            }
        }
    }
}
