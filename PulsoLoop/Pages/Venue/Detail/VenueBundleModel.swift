import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 时长包购买面板：选一档 → 服务端报价（会员价）→ 付款（Android `BundlePurchaseUiState`）。 */
struct BundlePurchaseState {
    var open = false
    var offerId: String?
    var quote: Loadable<BundlePriceQuote>?
    var paymentMethod: BundlePaymentMethod?
    var purchasing = false
    /** 已付款，等 webhook 让时长包生效。 */
    var processing = false
    var activated = false
    /** 电话 / 到店已提交，等球馆确认收款。 */
    var awaitingVenue = false
    var replacedPrevious = false
    var error: String?
}

/** 球馆详情的时长包（Android `VenueBundleViewModel`）：在售的包、我在这家还有多少时长、购买。 */
@MainActor
@Observable
final class VenueBundleModel {
    let venueId: String

    private(set) var venue: VenueDetail?
    private(set) var offers = Loadable<[BundleOffer]>()
    private(set) var usable = Loadable<[MyBundle]>(isLoading: false)
    private(set) var signedIn = false
    var purchase = BundlePurchaseState()

    @ObservationIgnored @Injected(\.bundleService) private var bundleService
    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored private var quoteTask: Task<Void, Never>?
    @ObservationIgnored private var sheetAutoOpened = false

    init(venueId: String) {
        self.venueId = venueId
    }

    var shownOffers: [BundleOffer] { venue?.bundleSalesOpen == true ? (offers.data ?? []).shown : [] }
    var heldMinutes: Int { (usable.data ?? []).reduce(0) { $0 + $1.remainingMinutes } }
    var purchaseMethods: [BundlePaymentMethod] { venue?.acceptedBundleMethods ?? [] }
    var canBuy: Bool { signedIn && !purchaseMethods.isEmpty && venue?.status == .published }
    var selectedOffer: BundleOffer? { shownOffers.first { $0.id == purchase.offerId } }
    /** 已上线运动入口里最低的场地时价，用来算省多少。 */
    var hourlyPrice: Double? {
        (venue?.sportEntries ?? []).filter { $0.status == .published }.compactMap(\.minHourlyPriceAmount).min()
    }

    func observe() async {
        await concurrently([
            {
                for await response in self.venueService.streamVenue(self.venueId) {
                    if case let .data(venue) = response { self.venue = venue }
                }
            },
            {
                for await response in self.bundleService.streamOffers(self.venueId) {
                    self.offers = self.offers.reduce(response)
                }
            },
            {
                var usableTask: Task<Void, Never>?
                for await session in self.sessionStore.state.values() {
                    let signedIn = session.isAuthValid && !session.currentProfileId.isEmpty
                    guard signedIn != self.signedIn || usableTask == nil else { continue }
                    self.signedIn = signedIn
                    usableTask?.cancel()
                    self.usable = Loadable(isLoading: signedIn)
                    guard signedIn else {
                        usableTask = Task {}
                        continue
                    }
                    let stream = self.bundleService.streamUsable(self.venueId, sport: .badminton)
                    usableTask = Task {
                        for await response in stream {
                            self.usable = self.usable.reduce(response)
                        }
                    }
                }
                usableTask?.cancel()
            },
        ])
    }

    func openSheet(_ offerId: String? = nil) {
        let initial = offerId ?? shownOffers.first?.id
        purchase = BundlePurchaseState(open: true, paymentMethod: purchaseMethods.first)
        if let initial { selectOffer(initial) }
    }

    /** 路由要求直接打开购买面板时只开一次。 */
    func openSheetOnce() {
        guard !sheetAutoOpened else { return }
        sheetAutoOpened = true
        openSheet()
    }

    func closeSheet() {
        quoteTask?.cancel()
        purchase = BundlePurchaseState()
    }

    func selectPaymentMethod(_ method: BundlePaymentMethod) {
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
        let service = bundleService
        let venueId = venueId
        quoteTask = Task {
            do {
                let quote = try await service.quote(venueId, offerId: offerId)
                guard !Task.isCancelled else { return }
                purchase.quote = Loadable(data: quote, isLoading: false)
            } catch {
                guard !Task.isCancelled else { return }
                purchase.quote = nil
                purchase.error = UiError(error).text(fallback: String(localized: "venue_bundle_purchase_failed"))
            }
        }
    }

    func purchaseBundle() async {
        guard let offerId = purchase.offerId, let method = purchase.paymentMethod, purchaseMethods.contains(method) else { return }
        guard !purchase.purchasing, purchase.quote?.data != nil, canBuy else { return }
        purchase.purchasing = true
        purchase.error = nil
        do {
            let result = try await bundleService.purchase(venueId, offerId: offerId, paymentMethod: method)
            purchase.purchasing = false
            if let key = result.publishableKey, let account = result.providerAccountId, let secret = result.clientSecret {
                switch await ConnectedPaymentSheet.present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret)) {
                case .completed:
                    purchase.processing = true
                    await awaitActivation(result.bundleId)
                case .canceled: break
                case let .failed(message): purchase.error = message
                }
            } else if result.awaitingConfirmation {
                purchase.awaitingVenue = true
                purchase.replacedPrevious = result.replacedPrevious
            } else if result.status == .active {
                purchase.activated = true
            } else {
                purchase.processing = true
                await awaitActivation(result.bundleId)
            }
        } catch {
            purchase.purchasing = false
            purchase.error = UiError(error).text(fallback: String(localized: "venue_bundle_purchase_failed"))
        }
    }

    /** 平台付款由 webhook 落库：轮询到这个包生效，再全部失效。 */
    private func awaitActivation(_ bundleId: String) async {
        for _ in 0 ..< VenueDetailModel.activationPollAttempts {
            if let latest = try? await bundleService.refetchMyBundle(bundleId), latest.status == .active {
                purchase.processing = false
                purchase.activated = true
                bundleService.invalidate()
                return
            }
            try? await Task.sleep(for: VenueDetailModel.activationPollInterval)
        }
        purchase.processing = false
        bundleService.invalidate()
    }
}

/** 球馆详情里的教练 / 课程 / 赛事，以及教练申请合作（Android `VenueProgramsViewModel`）。 */
@MainActor
@Observable
final class VenueProgramsModel {
    let venueId: String

    private(set) var coaches: [VenueCoach] = []
    private(set) var courses: [Course] = []
    private(set) var policy: CoachPolicy?
    /** 我（教练）和这家球馆的合作；nil = 没有进行中的。 */
    private(set) var myLink: VenueCoach?
    private(set) var applying = false
    private(set) var isCoach = false
    let tournaments: PagedList<VenueTournament, Int>

    @ObservationIgnored @Injected(\.coachService) private var coachService
    @ObservationIgnored @Injected(\.courseService) private var courseService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.venueEventBus) private var venueEventBus

    init(venueId: String) {
        self.venueId = venueId
        tournaments = Container.shared.tournamentService().pageAtVenue(venueId)
    }

    var applyState: CoachApplyState {
        switch myLink?.status {
        case .active: .partner
        case .pending: .pending
        default: policy?.acceptsCoachRequests == true ? .available : .closed
        }
    }

    func observe() async {
        await concurrently([
            { await self.tournaments.observe() },
            {
                for await info in self.profileStore.current.values() {
                    self.isCoach = info?.communityRoles.contains(.coach) == true
                    await self.load()
                }
            },
            {
                for await _ in self.venueEventBus.signals(where: { _ in true }) {
                    await self.load()
                }
            },
        ])
    }

    /** 球馆页的侧边区块：某个请求失败时那一块保持空。 */
    private func load() async {
        let coachService = coachService
        let courseService = courseService
        let venueId = venueId
        await concurrently([
            { if let value = try? await coachService.venueCoaches(venueId) { self.coaches = value } },
            { if let value = try? await courseService.venueCourses(venueId) { self.courses = value } },
            {
                guard self.isCoach else { return }
                if let value = try? await coachService.venueCoachPolicy(venueId) { self.policy = value }
            },
            {
                guard self.isCoach else { return }
                if let page = try? await coachService.myVenues([.pending, .active]) {
                    self.myLink = page.items.first { $0.venueId == venueId }
                }
            },
        ])
    }

    func applyAsCoach(_ message: String) async {
        guard !applying else { return }
        applying = true
        defer { applying = false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await coachService.applyToVenue(venueId, message: trimmed.isEmpty ? nil : trimmed)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "program_action_failed")
        }
    }
}
