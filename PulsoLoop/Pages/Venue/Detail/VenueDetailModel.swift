import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 会员购买面板：选等级 → 选时长 → 报价 → 付款（Android `MembershipPurchaseUiState`）。 */
struct MembershipPurchaseState {
    var open = false
    var levelId: String?
    var offerId: String?
    var quote: Loadable<MembershipPriceQuote>?
    var purchasing = false
    /** 已付款，等 webhook 开卡。 */
    var processing = false
    var activated = false
    /** 电话 / 到店已提交，等球馆确认收款。 */
    var awaitingVenue = false
    var replacedPrevious = false
    /** 显示在面板里（面板盖在全局提示上面）。 */
    var error: String?
    var paymentMethod: MembershipPaymentMethod?
}

/**
 * 球馆详情（Android `VenueDetailViewModel`）：球馆、每个已上线运动的规则和场地、商品服务、会员方案和我的会员、
 * 这栋建筑办的活动；会员购买。打开一次计一次浏览（工作人员打开不计）。
 */
@MainActor
@Observable
final class VenueDetailModel {
    static let activationPollAttempts = 10
    static let activationPollInterval = Duration.seconds(2)

    let venueId: String

    private(set) var venue = Loadable<VenueDetail>()
    var tab = VenueInfoTab.overview
    /** 这栋建筑办的活动（「活动」分段）。 */
    let buildingEvents = BuildingEvents()
    private(set) var sport: VenueSport?
    private(set) var entries: [VenueSport: Loadable<CourtEntryUi>] = [:]
    private(set) var courts: [VenueSport: [CourtUi]] = [:]
    private(set) var offers = Loadable<MembershipOffersGrid>()
    private(set) var myMembership = Loadable<MyVenueMembership>(isLoading: false)
    private(set) var signedIn = false
    var purchase = MembershipPurchaseState()
    private(set) var offerings = Loadable<[VenueOffering]>()
    /** 设备位置；还没定位时 nil，不显示距离。 */
    private(set) var myLocation: PickedLocation?
    /** 位置预览的地图样式（地图偏好）。 */
    private(set) var map = ResolvedMapPreference()

    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.membershipService) private var membershipService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.exploreFocusStore) private var focusStore
    @ObservationIgnored @Injected(\.preferenceService) private var preferenceService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let venueServices = Container.shared.venueSportServices()
    @ObservationIgnored private var session = AuthSession.loggedOut
    @ObservationIgnored private var sportsTask: Task<Void, Never>?
    @ObservationIgnored private var quoteTask: Task<Void, Never>?
    @ObservationIgnored private var loadedSports: [VenueSport] = []
    @ObservationIgnored private var viewCounted = false
    @ObservationIgnored private var membershipSheetAutoOpened = false

    init(venueId: String) {
        self.venueId = venueId
    }

    /* ------------------------------ 派生 ------------------------------ */

    /** 我到球馆的直线距离（米）。 */
    var distanceM: Double? {
        guard let me = myLocation, let lat = venue.data?.building.locationLat, let lng = venue.data?.building.locationLng else { return nil }
        return haversineM(me.latitude, me.longitude, lat, lng)
    }

    var activeOfferings: [VenueOffering] { (offerings.data ?? []).filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder } }
    var sports: [VenueSport] { venue.data?.publishedSports ?? [] }
    var mine: MyMembership? { myMembership.data?.membership }
    var activeMembership: MyMembership? { mine?.status == .active ? mine : nil }
    var shownOffers: [MembershipOffer] { (offers.data?.offers ?? []).filter { $0.priceAmount != nil } }
    var purchaseMethods: [MembershipPaymentMethod] { venue.data?.acceptedMembershipMethods ?? [] }
    var canBuy: Bool { !purchaseMethods.isEmpty }

    func offersForLevel(_ levelId: String?) -> [MembershipOffer] {
        shownOffers.filter { $0.levelId == levelId }.sorted { ($0.durationMonths ?? .max) < ($1.durationMonths ?? .max) }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /* ------------------------------ 订阅 ------------------------------ */

    func observe() async {
        await concurrently([
            {
                for await response in self.venueService.streamVenue(self.venueId) {
                    self.venue = self.venue.reduce(response)
                    if case let .data(venue) = response { self.maybeIncrementView(isPublicViewer: venue.myRole == nil) }
                    let sports = self.sports
                    if self.sport == nil || !sports.contains(self.sport!) { self.sport = sports.first }
                    if sports != self.loadedSports { self.loadSports(sports) }
                    self.buildingEvents.load(buildingId: self.venue.data?.building.id ?? "", session: self.session)
                }
            },
            {
                for await response in self.venueService.streamOfferings(self.venueId) {
                    self.offerings = self.offerings.reduce(response)
                }
            },
            {
                for await preference in self.preferenceService.preference.values() {
                    self.map = preference.map
                }
            },
            {
                for await device in self.deviceLocation.location.values() {
                    self.myLocation = device?.point
                }
            },
            {
                for await response in self.membershipService.streamOffers(self.venueId) {
                    self.offers = self.offers.reduce(response)
                }
            },
            {
                var mineTask: Task<Void, Never>?
                for await session in self.sessionStore.state.values() {
                    self.session = session
                    let signedIn = session.isAuthValid && !session.currentProfileId.isEmpty
                    self.buildingEvents.load(buildingId: self.venue.data?.building.id ?? "", session: session)
                    guard signedIn != self.signedIn || mineTask == nil else { continue }
                    self.signedIn = signedIn
                    mineTask?.cancel()
                    self.myMembership = Loadable(isLoading: signedIn)
                    guard signedIn else {
                        mineTask = Task {}
                        continue
                    }
                    let stream = self.membershipService.streamMine(self.venueId)
                    mineTask = Task {
                        for await response in stream {
                            self.myMembership = self.myMembership.reduce(response)
                        }
                    }
                }
                mineTask?.cancel()
            },
        ])
        sportsTask?.cancel()
        buildingEvents.cancel()
    }

    /** 每个已上线运动的规则和场地：场地分段显示选中的那个，须知分段全部列出。 */
    private func loadSports(_ sports: [VenueSport]) {
        loadedSports = sports
        sportsTask?.cancel()
        let venueId = venueId
        let operations: [@MainActor () async -> Void] = sports.compactMap { sport in
            guard let service = venueServices[sport] else { return nil }
            return {
                await concurrently([
                    {
                        for await response in service.entry(venueId: venueId) {
                            self.entries[sport] = (self.entries[sport] ?? Loadable()).reduce(response)
                        }
                    },
                    {
                        for await response in service.courts(venueId: venueId) {
                            if case let .data(courts) = response { self.courts[sport] = courts }
                        }
                    },
                ])
            }
        }
        sportsTask = Task { await concurrently(operations) }
    }

    /** 打开一次计一次；工作人员打开不计。 */
    private func maybeIncrementView(isPublicViewer: Bool) {
        guard !viewCounted, isPublicViewer else { return }
        viewCounted = true
        let service = venueService
        let venueId = venueId
        Task { try? await service.incrementView(venueId) }
    }

    /* ------------------------------ 操作 ------------------------------ */

    func selectSport(_ value: VenueSport) {
        sport = value
    }

    func refresh() {
        venueService.invalidate()
    }

    /** 「在地图上看」：Explore 飞到这家球馆并选中它。 */
    func focusOnExplore() -> Bool {
        guard let building = venue.data?.building, let lat = building.locationLat, let lng = building.locationLng else { return false }
        focusStore.request(ExploreFocus(eventId: nil, latitude: lat, longitude: lng, venueId: venueId))
        return true
    }

    var bookRoute: LoopRoute? {
        sport.map { .venueBook(venueId: venueId, sport: $0) }
    }

    /* ------------------------------ 会员购买 ------------------------------ */

    func openMembershipSheet() {
        let levels = (offers.data?.levels ?? []).filter { level in shownOffers.contains { $0.levelId == level.id } }
        let levelId = activeMembership.flatMap { active in levels.contains { $0.id == active.levelId } ? active.levelId : nil }
            ?? levels.min { $0.rank < $1.rank }?.id
        purchase = MembershipPurchaseState(open: true, levelId: levelId, paymentMethod: purchaseMethods.first)
    }

    /** 路由要求直接打开方案时只开一次；关掉后不会因数据刷新再弹出。 */
    func openMembershipSheetOnce() {
        guard !membershipSheetAutoOpened else { return }
        membershipSheetAutoOpened = true
        openMembershipSheet()
    }

    func closeMembershipSheet() {
        quoteTask?.cancel()
        purchase = MembershipPurchaseState()
    }

    func selectLevel(_ levelId: String) {
        quoteTask?.cancel()
        purchase.levelId = levelId
        purchase.offerId = nil
        purchase.quote = nil
        purchase.error = nil
    }

    func selectPaymentMethod(_ method: MembershipPaymentMethod) {
        purchase.paymentMethod = method
        purchase.error = nil
    }

    func selectOffer(_ offerId: String) {
        quoteTask?.cancel()
        purchase.offerId = offerId
        purchase.quote = signedIn ? Loadable() : nil
        purchase.error = nil
        purchase.activated = false
        purchase.awaitingVenue = false
        purchase.replacedPrevious = false
        guard signedIn else { return }
        // 降级不报价。
        if let active = activeMembership, let offer = shownOffers.first(where: { $0.id == offerId }), offer.rank < active.rank { return }
        let service = membershipService
        let venueId = venueId
        quoteTask = Task {
            do {
                let quote = try await service.quote(venueId, offerId: offerId)
                guard !Task.isCancelled else { return }
                purchase.quote = Loadable(data: quote, isLoading: false)
            } catch {
                guard !Task.isCancelled else { return }
                purchase.quote = nil
                purchase.error = UiError(error).text(fallback: String(localized: "venue_membership_purchase_failed"))
            }
        }
    }

    func purchaseMembership() async {
        guard let offerId = purchase.offerId, let method = purchase.paymentMethod, purchaseMethods.contains(method) else { return }
        guard !purchase.purchasing, purchase.quote?.data != nil, canBuy else { return }
        let before = mine
        purchase.purchasing = true
        purchase.error = nil
        do {
            let result = try await membershipService.purchase(venueId, offerId: offerId, paymentMethod: method)
            purchase.purchasing = false
            if let key = result.publishableKey, let account = result.providerAccountId, let secret = result.clientSecret {
                switch await ConnectedPaymentSheet.present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret)) {
                case .completed:
                    purchase.processing = true
                    await awaitActivation(before: before)
                case .canceled: break
                case let .failed(message): purchase.error = message
                }
            } else if result.awaitingConfirmation {
                purchase.awaitingVenue = true
                purchase.replacedPrevious = result.replacedPrevious
                membershipService.invalidate()
            } else {
                purchase.processing = true
                await awaitActivation(before: before)
            }
        } catch {
            purchase.purchasing = false
            purchase.error = UiError(error).text(fallback: String(localized: "venue_membership_purchase_failed"))
        }
    }

    /** 开卡由付款 webhook 落库：轮询到「我的会员」变了，再全部失效。 */
    private func awaitActivation(before: MyMembership?) async {
        for _ in 0 ..< Self.activationPollAttempts {
            if let latest = try? await membershipService.refetchMine(venueId).membership, latest != before, latest.status == .active {
                myMembership = Loadable(data: MyVenueMembership(membership: latest), isLoading: false)
                purchase.processing = false
                purchase.activated = true
                membershipService.invalidate()
                return
            }
            try? await Task.sleep(for: Self.activationPollInterval)
        }
        purchase.processing = false
        membershipService.invalidate()
    }
}
