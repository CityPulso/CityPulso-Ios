import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选桌台（Android `<ActivityType>VenueBookViewModel`，按桌台订的类型共用，差别在 [VenueActivityTypeService]）：选日期，在表上点 / 拖选时段，
 * 底部显示已选几段、合计（会员看到折后价）和成为会员能省多少；够了就去确认页。
 */
@MainActor
@Observable
final class VenueBookModel {
    let venueId: String

    private(set) var venue = Loadable<VenueDetail>()
    let activityType: VenueActivityType
    /** 当前活动类型的入口规则；切活动类型时回到加载中。 */
    private(set) var entry = Loadable<SpaceEntryUi>()
    private(set) var dateKeys: [String] = []
    private(set) var dateKey: String?
    private(set) var day = Loadable<SpaceDayUi>()
    private(set) var selection: BoardSelection = [:]
    private(set) var offers = Loadable<MembershipOffersGrid>()
    private(set) var myMembership = Loadable<MyVenueMembership>(isLoading: false)
    private(set) var spaces: [SpaceUi] = []
    private(set) var ratePlans: [SpaceRatePlanUi] = []

    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.membershipService) private var membershipService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let services = Container.shared.venueActivityTypeServices()
    @ObservationIgnored private var activityTypeTask: Task<Void, Never>?
    @ObservationIgnored private var dayTask: Task<Void, Never>?

    init(venueId: String, activityType: VenueActivityType) {
        self.venueId = venueId
        self.activityType = activityType
    }

    private var service: any VenueActivityTypeService { services[activityType]! }

    /* ------------------------------ 派生 ------------------------------ */

    /** 门店已上线的活动类型；超过一个才显示切换。 */
    var activityTypes: [VenueActivityType] { venue.data?.publishedActivityTypes ?? [] }
    /** 表头带上价格方案名和场地照片。 */
    var board: SpaceDayUi? { day.data?.withMeta(spaces: spaces, plans: ratePlans.sorted { $0.sortOrder < $1.sortOrder }, imageURL: imageURL) }
    var lines: [SpaceLineUi] { selection.lines(day.data) }
    var totalCents: Int { lines.reduce(0) { $0 + $1.priceCents } }
    /** 有效会员看到折后价；原价划掉。 */
    var pricing: SpaceCheckoutPricing { SpaceCheckoutPricing(linePriceCents: lines.map(\.priceCents), membership: myMembership.data?.membership) }
    var selectionError: String? {
        guard let entry = entry.data, let error = validateSpaceSelection(lines, minBookingMinutes: entry.minBookingMinutes, maxBookingMinutes: entry.maxBookingMinutes) else { return nil }
        return error.text(minBookingMinutes: entry.minBookingMinutes, maxBookingMinutes: entry.maxBookingMinutes)
    }

    var isBookable: Bool { entry.data.map { $0.status == .published && $0.venueStatus == .published } ?? false }
    /** 不是会员时，在售等级里折扣最高的一级。 */
    var bestMemberLevel: MembershipLevel? { bestUpsellLevel(offers.data, membership: myMembership.data?.membership) }
    var memberSaveCents: Int { upsellSaveCents(bestMemberLevel, totalCents: totalCents) }
    var canGoToConfirm: Bool {
        isBookable && dateKey != nil && !lines.isEmpty && selectionError == nil && day.data?.bookable == true
    }

    func imageURL(_ imageId: String) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /* ------------------------------ 订阅 ------------------------------ */

    func observe() async {
        loadActivityType()
        await concurrently([
            {
                for await response in self.venueService.streamVenue(self.venueId) {
                    self.venue = self.venue.reduce(response)
                }
            },
            {
                for await response in self.membershipService.streamOffers(self.venueId) {
                    self.offers = self.offers.reduce(response)
                }
            },
            {
                var mine: Task<Void, Never>?
                for await session in self.sessionStore.state.values() {
                    mine?.cancel()
                    let signedIn = session.isAuthValid && !session.currentProfileId.isEmpty
                    self.myMembership = Loadable(isLoading: signedIn)
                    guard signedIn else { continue }
                    let stream = self.membershipService.streamMine(self.venueId)
                    mine = Task {
                        for await response in stream {
                            self.myMembership = self.myMembership.reduce(response)
                        }
                    }
                }
                mine?.cancel()
            },
        ])
        activityTypeTask?.cancel()
        dayTask?.cancel()
    }

    /** 当前活动类型的规则、场地和价格方案；规则回来后定日期范围。 */
    private func loadActivityType() {
        activityTypeTask?.cancel()
        entry = Loadable()
        spaces = []
        ratePlans = []
        let service = service
        let venueId = venueId
        activityTypeTask = Task {
            await concurrently([
                {
                    for await response in service.entry(venueId: venueId) {
                        self.entry = self.entry.reduce(response)
                        if let entry = self.entry.data {
                            self.dateKeys = VenueTime.dateKeys(timezone: entry.timezone, days: entry.bookingWindowDays)
                        }
                        // 切活动类型时保留已选日期（仍在新入口的预订窗口内才保留）。
                        if self.dateKey == nil || !self.dateKeys.contains(self.dateKey!) {
                            self.dateKey = self.dateKeys.first
                            self.loadDay()
                        }
                    }
                },
                {
                    for await response in service.spaces(venueId: venueId) {
                        if case let .data(spaces) = response { self.spaces = spaces }
                    }
                },
                {
                    for await response in service.ratePlans(venueId: venueId) {
                        if case let .data(plans) = response { self.ratePlans = plans }
                    }
                },
            ])
        }
    }

    /** 某天的表；重拉后去掉已经不能订的格子。 */
    private func loadDay() {
        dayTask?.cancel()
        day = Loadable()
        selection = [:]
        guard let dateKey else { return }
        let stream = service.availability(venueId: venueId, date: dateKey)
        dayTask = Task {
            for await response in stream {
                guard !Task.isCancelled else { return }
                day = day.reduce(response)
                if let data = day.data { selection = selection.pruned(data) }
            }
        }
    }

    /* ------------------------------ 操作 ------------------------------ */

    func refresh() {
        venueService.invalidate()
    }


    func selectDate(_ key: String) {
        guard key != dateKey else { return }
        dateKey = key
        loadDay()
    }

    func tap(_ spaceId: String, _ index: Int) {
        guard let space = day.data?.spaces.first(where: { $0.spaceId == spaceId }) else { return }
        selection = selection.tapping(space, index)
    }

    func paint(_ spaceId: String, _ index: Int) {
        guard let space = day.data?.spaces.first(where: { $0.spaceId == spaceId }) else { return }
        selection = selection.painting(space, index)
    }

    /** 底部已选栏里某一段的 ×。 */
    func remove(_ line: SpaceLineUi) {
        guard let space = day.data?.spaces.first(where: { $0.spaceId == line.spaceId }) else { return }
        selection = selection.withoutRun(space, startsAt: line.startsAt, endsAt: line.endsAt)
    }

    func clearSelection() {
        selection = [:]
    }

    /** 去确认页要带的路由；还不能去时 nil。 */
    var confirmRoute: NearRoute? {
        guard canGoToConfirm, let dateKey else { return nil }
        return .venueConfirm(venueId: venueId, activityType: activityType, date: dateKey, ranges: selection.confirmRanges)
    }
}
