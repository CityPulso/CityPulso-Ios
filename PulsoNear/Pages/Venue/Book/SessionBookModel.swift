import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选场次（Android `EscapeRoomVenueBookViewModel` / `ScriptMurderVenueBookViewModel`，差别在 [SessionVenueService]）：
 * 选日期，再选某个主题 / 剧本的一个开始时间和人数；底部显示这一场的价格（会员看到折后价）和成为会员能省多少。
 */
@MainActor
@Observable
final class SessionBookModel {
    let venueId: String
    let activityType: VenueActivityType

    private(set) var venue = Loadable<VenueDetail>()
    private(set) var entry = Loadable<SessionEntryUi>()
    private(set) var options = Loadable<[SessionOptionUi]>()
    private(set) var dateKeys: [String] = []
    private(set) var dateKey: String?
    private(set) var day = Loadable<SessionDayUi>()
    /** 选中的一场；表里不再有空位时清掉。 */
    private(set) var pick: (optionId: String, startsAt: String)?
    /** 用户调过的人数；0 = 用主题 / 剧本的最少人数。 */
    private(set) var partySize = 0
    private(set) var offers = Loadable<MembershipOffersGrid>()
    private(set) var myMembership = Loadable<MyVenueMembership>(isLoading: false)

    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.membershipService) private var membershipService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored private let service: any SessionVenueService
    @ObservationIgnored private var dayTask: Task<Void, Never>?

    init(venueId: String, activityType: VenueActivityType) {
        self.venueId = venueId
        self.activityType = activityType
        service = Container.shared.sessionVenueServices()[activityType]!
    }

    /* ------------------------------ 派生 ------------------------------ */

    var activityTypes: [VenueActivityType] { venue.data?.publishedActivityTypes ?? [] }
    var pickedOption: SessionOptionUi? { pick.flatMap { pick in options.data?.first { $0.id == pick.optionId } } }
    var pickedSlot: SessionSlotUi? {
        pick.flatMap { pick in day.data?.rows.first { $0.optionId == pick.optionId }?.slots.first { $0.startsAt == pick.startsAt } }
    }

    /** 人数夹在选中主题 / 剧本的人数范围里（WEB `clampEscapeRoomPartySize`）。 */
    var party: Int {
        guard let option = pickedOption else { return 0 }
        return min(max(partySize > 0 ? partySize : option.playersMin, option.playersMin), option.playersMax)
    }

    var priceCents: Int? {
        guard let option = pickedOption, let slot = pickedSlot else { return nil }
        return sessionPriceCents(slot.priceCents, extraPlayerAmount: option.extraPlayerAmount, playersMin: option.playersMin, partySize: party)
    }

    var pricing: SpaceCheckoutPricing { SpaceCheckoutPricing(linePriceCents: priceCents.map { [$0] } ?? [], membership: myMembership.data?.membership) }
    var isBookable: Bool { entry.data.map { $0.status == .published && $0.venueStatus == .published } ?? false }
    var bestMemberLevel: MembershipLevel? { bestUpsellLevel(offers.data, membership: myMembership.data?.membership) }
    var memberSaveCents: Int { upsellSaveCents(bestMemberLevel, totalCents: priceCents ?? 0) }

    /** 每个主题 / 剧本一行，带上它的人数和标签（密室是难度，剧本杀是题材）。 */
    var rows: [(row: SessionRowUi, option: SessionOptionUi?)]? {
        day.data.map { day in
            day.rows.sorted { $0.sortOrder < $1.sortOrder }.map { row in (row, options.data?.first { $0.id == row.optionId }) }
        }
    }

    var canGoToConfirm: Bool {
        isBookable && dateKey != nil && pickedSlot?.available == true && pickedOption != nil && day.data?.bookable == true
    }

    var confirmRoute: NearRoute? {
        guard canGoToConfirm, let dateKey, let pick else { return nil }
        return .venueConfirm(venueId: venueId, activityType: activityType, date: dateKey, target: .session(VenueSessionPick(optionId: pick.optionId, startsAt: pick.startsAt, partySize: party)))
    }

    /* ------------------------------ 订阅 ------------------------------ */

    func observe() async {
        await concurrently([
            {
                for await response in self.venueService.streamVenue(self.venueId) {
                    self.venue = self.venue.reduce(response)
                }
            },
            {
                for await response in self.service.options(venueId: self.venueId) {
                    self.options = self.options.reduce(response)
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
            {
                for await response in self.service.entry(venueId: self.venueId) {
                    self.entry = self.entry.reduce(response)
                    if let entry = self.entry.data {
                        self.dateKeys = VenueTime.dateKeys(timezone: entry.timezone, days: entry.bookingWindowDays)
                    }
                    if self.dateKey == nil || !self.dateKeys.contains(self.dateKey!) {
                        self.dateKey = self.dateKeys.first
                        self.loadDay()
                    }
                }
            },
        ])
        dayTask?.cancel()
    }

    /** 某天的场次；重拉后选中的那场没空位了就清掉。 */
    private func loadDay() {
        dayTask?.cancel()
        day = Loadable()
        pick = nil
        guard let dateKey else { return }
        let stream = service.availability(venueId: venueId, date: dateKey)
        dayTask = Task {
            for await response in stream {
                guard !Task.isCancelled else { return }
                day = day.reduce(response)
                if pick != nil, pickedSlot?.available != true { pick = nil }
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

    /** 再点一次选中的那场就取消；换了主题 / 剧本人数回到最少人数。 */
    func select(optionId: String, startsAt: String) {
        if let pick, pick.optionId == optionId, pick.startsAt == startsAt {
            self.pick = nil
            return
        }
        if pick?.optionId != optionId { partySize = 0 }
        pick = (optionId, startsAt)
    }

    func setPartySize(_ size: Int) {
        partySize = size
    }
}
