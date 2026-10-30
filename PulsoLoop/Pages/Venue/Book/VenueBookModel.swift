import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选场（Android `<Sport>VenueBookViewModel`，三种运动共用，差别在 [VenueSportService]）：选运动、日期，在表上点 / 拖选时段，
 * 底部显示已选几段、合计（会员看到折后价）和成为会员能省多少；够了就去确认页。
 */
@MainActor
@Observable
final class VenueBookModel {
    let venueId: String

    private(set) var venue = Loadable<VenueDetail>()
    private(set) var sport: VenueSport
    /** 当前运动的入口规则；切运动时回到加载中。 */
    private(set) var entry = Loadable<CourtEntryUi>()
    private(set) var dateKeys: [String] = []
    private(set) var dateKey: String?
    private(set) var day = Loadable<CourtDayUi>()
    private(set) var selection: BoardSelection = [:]
    private(set) var offers = Loadable<MembershipOffersGrid>()
    private(set) var myMembership = Loadable<MyVenueMembership>(isLoading: false)
    private(set) var courts: [CourtUi] = []
    private(set) var ratePlans: [CourtRatePlanUi] = []

    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.membershipService) private var membershipService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let services = Container.shared.venueSportServices()
    @ObservationIgnored private var sportTask: Task<Void, Never>?
    @ObservationIgnored private var dayTask: Task<Void, Never>?

    init(venueId: String, sport: VenueSport) {
        self.venueId = venueId
        self.sport = sport
    }

    private var service: any VenueSportService { services[sport]! }

    /* ------------------------------ 派生 ------------------------------ */

    /** 球馆已上线的运动；超过一个才显示切换。 */
    var sports: [VenueSport] { venue.data?.publishedSports ?? [] }
    /** 表头带上价格方案名和场地照片。 */
    var board: CourtDayUi? { day.data?.withMeta(courts: courts, plans: ratePlans.sorted { $0.sortOrder < $1.sortOrder }, imageURL: imageURL) }
    var lines: [CourtLineUi] { selection.lines(day.data) }
    var totalCents: Int { lines.reduce(0) { $0 + $1.priceCents } }
    /** 有效会员看到折后价；原价划掉。 */
    var pricing: CourtCheckoutPricing { CourtCheckoutPricing(linePriceCents: lines.map(\.priceCents), membership: myMembership.data?.membership) }
    var selectionError: String? {
        guard let entry = entry.data, let error = validateCourtSelection(lines, minBookingMinutes: entry.minBookingMinutes, maxBookingMinutes: entry.maxBookingMinutes) else { return nil }
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
        loadSport()
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
        sportTask?.cancel()
        dayTask?.cancel()
    }

    /** 当前运动的规则、场地和价格方案；规则回来后定日期范围。 */
    private func loadSport() {
        sportTask?.cancel()
        entry = Loadable()
        courts = []
        ratePlans = []
        let service = service
        let venueId = venueId
        sportTask = Task {
            await concurrently([
                {
                    for await response in service.entry(venueId: venueId) {
                        self.entry = self.entry.reduce(response)
                        if let entry = self.entry.data {
                            self.dateKeys = VenueTime.dateKeys(timezone: entry.timezone, days: entry.bookingWindowDays)
                        }
                        // 切运动时保留已选日期（仍在新入口的预订窗口内才保留）。
                        if self.dateKey == nil || !self.dateKeys.contains(self.dateKey!) {
                            self.dateKey = self.dateKeys.first
                            self.loadDay()
                        }
                    }
                },
                {
                    for await response in service.courts(venueId: venueId) {
                        if case let .data(courts) = response { self.courts = courts }
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

    func selectSport(_ next: VenueSport) {
        guard next != sport else { return }
        sport = next
        loadSport()
        loadDay()
    }

    func selectDate(_ key: String) {
        guard key != dateKey else { return }
        dateKey = key
        loadDay()
    }

    func tap(_ courtId: String, _ index: Int) {
        guard let court = day.data?.courts.first(where: { $0.courtId == courtId }) else { return }
        selection = selection.tapping(court, index)
    }

    func paint(_ courtId: String, _ index: Int) {
        guard let court = day.data?.courts.first(where: { $0.courtId == courtId }) else { return }
        selection = selection.painting(court, index)
    }

    /** 底部已选栏里某一段的 ×。 */
    func remove(_ line: CourtLineUi) {
        guard let court = day.data?.courts.first(where: { $0.courtId == line.courtId }) else { return }
        selection = selection.withoutRun(court, startsAt: line.startsAt, endsAt: line.endsAt)
    }

    func clearSelection() {
        selection = [:]
    }

    /** 去确认页要带的路由；还不能去时 nil。 */
    var confirmRoute: LoopRoute? {
        guard canGoToConfirm, let dateKey else { return nil }
        return .venueConfirm(venueId: venueId, sport: sport, date: dateKey, ranges: selection.confirmRanges)
    }
}

extension VenueDetail {
    /** 已上线的运动入口（工作人员能看到草稿入口，球友一律只认已上线的）。 */
    var publishedSports: [VenueSport] {
        sportEntries.filter { $0.status == .published }.map(\.sport)
    }

    var displayName: String { building.name }

    /** 订场接受的方式，在线付款在前（WEB `CheckoutPanel`）；时长包不是球馆开关，由确认页按可用的包放到最前。 */
    var acceptedMethods: [CourtBookingPaymentMethod] {
        [.platform, .phone, .offline].filter { method in
            switch method {
            case .platform: acceptsPlatform
            case .phone: acceptsPhone
            case .offline: acceptsOffline
            case .bundle: false
            }
        }
    }

    var acceptedMembershipMethods: [MembershipPaymentMethod] {
        [.platform, .phone, .offline].filter { method in
            switch method {
            case .platform: membershipAcceptsPlatform
            case .phone: membershipAcceptsPhone
            case .offline: membershipAcceptsOffline
            }
        }
    }

    var acceptedBundleMethods: [BundlePaymentMethod] {
        [.platform, .phone, .offline].filter { method in
            switch method {
            case .platform: bundleAcceptsPlatform
            case .phone: bundleAcceptsPhone
            case .offline: bundleAcceptsOffline
            }
        }
    }
}
