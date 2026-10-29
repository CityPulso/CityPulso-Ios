import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 详情页上同一时间最多一个的弹层（Android `EventSheet`）。 */
enum EventSheet: Identifiable {
    case join
    case waitlist
    case joinSuccess
    case waitlistSuccess
    case myRegistration
    case exit
    case participants

    var id: Self { self }
}

/** 可点「退出」：参加中、排队或占座待付（待退出应该「取消退出」，不是退出）。 */
private let exitableStatuses: Set<RegistrationStatus> = [.participating, .waitlisted, .awaitingPayment]
/** 可看收款清单：主办，或已入场（排队不算）。 */
private let checklistStatuses: Set<RegistrationStatus> = [.participating, .pendingExit]
/** 占名额的：参加中、待退出、占座待付。 */
private let seatStatuses: Set<RegistrationStatus> = [.participating, .pendingExit, .awaitingPayment]

/**
 * 活动详情（对应 Android `<Sport>EventViewModel` + `<Sport>UiState`，所有运动共用）：活动、名单、我的报名，
 * 报名 / 候补 / 退出 / 结束 / 改基本信息，占座付款。各运动的差别在 [SportEventDetailService] 和 DTO 的协议实现里。
 */
@MainActor
@Observable
final class EventDetailModel {
    private static let settlingPoll = Duration.seconds(5)

    let sport: LoopSport
    let eventId: String

    private(set) var event: (any SportFullEvent)?
    private(set) var imageIds: [String] = []
    private(set) var isEventLoading = true
    private(set) var eventError: UiError?
    private(set) var registrations: [any SportRegistration] = []
    private(set) var rosterReady = false
    private(set) var rosterTotal = 0
    private(set) var isRosterLoading = true
    private(set) var isRosterLoadingMore = false
    private(set) var rosterError: UiError?
    private(set) var isHost = false
    private(set) var hostDisplayName: String?
    private(set) var hostAvatarImageId: String?
    private(set) var myRegistration: (any SportRegistration)?
    private(set) var isActionInProgress = false
    /** 报名 / 候补 / 退出弹层里就地显示的失败。 */
    private(set) var actionError: String?
    /** 非空时弹出占座付款面板（报名后或「立即付款」）。 */
    var paymentSession: PaymentHoldSession?
    private(set) var isPaymentLoading = false
    /** 付款面板已完成、等 webhook 落库。 */
    private(set) var paidPending = false
    private(set) var isPulser = false
    private(set) var viewerDisplayName: String?
    private(set) var viewerAvatarImageId: String?
    private(set) var viewerUsername: String?
    var sheet: EventSheet?

    @ObservationIgnored private let service: any LoopSportService
    @ObservationIgnored @Injected(\.authQueryStore) private var authQueries
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var viewCounted = false
    @ObservationIgnored private var loadedHostProfileId: String?

    init(sport: LoopSport, eventId: String) {
        self.sport = sport
        self.eventId = eventId
        service = Container.shared.loopSportServices()[sport]!
    }

    /* ------------------------------ 推导 ------------------------------ */

    /** 主办绑了收款账户，而且收费方式里有刷卡。 */
    var acceptsStripe: Bool {
        guard let event else { return false }
        return event.payeePaymentAccountId != nil && event.paymentMethodList.contains { $0.kind == .stripe }
    }

    var offlineMethods: [EventPaymentKind] {
        event?.paymentMethodList.map(\.kind).filter { $0 != .stripe } ?? []
    }

    /** 同时接受刷卡和线下方式时让报名者选（WEB Registration modal `offersChoice`）。 */
    var offersPayChoice: Bool {
        event?.isFree == false && acceptsStripe && !offlineMethods.isEmpty
    }

    /** 我的报名还在结算（占座待付 / 退款中）时轮询。 */
    var isPaymentSettling: Bool {
        myRegistration?.status == .awaitingPayment || myRegistration?.refund == .pending
    }

    var activeSeats: Int {
        guard let event else { return 0 }
        return event.participatingCount + event.pendingExitCount + event.awaitingPaymentCount
    }

    var remainingSeats: Int { max(0, (event?.capacity ?? 0) - activeSeats) }
    /** 已占的名额里，申请退出、等候补顶上的人。 */
    var leavingSeats: Int { event?.pendingExitCount ?? 0 }
    var isFull: Bool { activeSeats >= (event?.capacity ?? 0) }

    var openStatus: EventOpenStatus {
        if event?.isEnded == true { return .ended }
        return isFull ? .full : .open
    }

    var hasWaitlistRoom: Bool { (event?.waitlistedCount ?? 0) < (event?.waitlistCapacity ?? 0) }
    var canJoinDirectly: Bool { rosterReady && myRegistration == nil && !isFull && event?.isEnded != true }
    /** 名额满了才出现候补。 */
    var canJoinWaitlist: Bool { rosterReady && myRegistration == nil && isFull && hasWaitlistRoom && event?.isEnded != true }
    var canExit: Bool {
        rosterReady && !isHost && event?.isEnded != true && myRegistration.map { exitableStatuses.contains($0.status) } == true
    }
    var canRejoin: Bool { rosterReady && event?.isEnded != true && myRegistration?.status == .pendingExit }
    /** 有一条可以打开的「我的报名」（退出了的不算）。 */
    var hasRegistration: Bool { myRegistration.map { $0.status != .exited } ?? false }
    var joinBlockedByProfile: Bool { !isPulser && (canJoinDirectly || canJoinWaitlist || canRejoin) }
    /** 免费活动没有收款，就没有收款清单。 */
    var canOpenChecklist: Bool {
        event?.isFree == false && (isHost || myRegistration.map { checklistStatuses.contains($0.status) } == true)
    }

    var seatedRegistrations: [any SportRegistration] { registrations.filter { seatStatuses.contains($0.status) } }
    var waitlistedRegistrations: [any SportRegistration] { registrations.filter { $0.status == .waitlisted } }
    var rosterHasMore: Bool { registrations.count < rosterTotal }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    var imageURLs: [URL] { imageIds.compactMap { imageURL($0) } }

    /* ------------------------------ 订阅 ------------------------------ */

    /** 活动、名单、当前身份，外加结算中的轮询；页面消失时随 `.task` 取消。 */
    func observe() async {
        let detail = service.detail(eventId: eventId)
        let roster = service.roster(eventId: eventId)
        await concurrently([
            {
                for await info in self.profileStore.current.values() {
                    self.isPulser = info?.isPulser == true
                    self.viewerDisplayName = info?.displayName.flatMap { $0.isEmpty ? nil : $0 }
                    self.viewerAvatarImageId = info?.avatarImageId
                    self.viewerUsername = info.flatMap { $0.citypulsoId != $0.profileId ? $0.citypulsoId : nil }
                }
            },
            {
                for await response in detail { self.applyDetail(response) }
            },
            {
                for await response in roster { self.applyRoster(response) }
            },
            {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.settlingPoll)
                    if self.isPaymentSettling { self.service.invalidate() }
                }
            },
        ])
    }

    func refresh() {
        service.invalidate()
    }

    func loadMoreRoster() async {
        guard rosterReady, rosterHasMore, !isRosterLoadingMore else { return }
        isRosterLoadingMore = true
        defer { isRosterLoadingMore = false }
        do {
            let page = try await service.rosterPage(eventId: eventId, offset: registrations.count)
            registrations += page.items
            rosterTotal = page.total
            myRegistration = myRegistrationIn(registrations) ?? myRegistration
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "event_detail_roster_more_failed")
        }
    }

    private func applyDetail(_ response: QueryResponse<EventDetail>) {
        switch response {
        case let .data(detail):
            isEventLoading = false
            eventError = nil
            event = detail.event
            imageIds = detail.imageIds
            let myProfileId = profileStore.current.value?.profileId
            isHost = myProfileId != nil && myProfileId == detail.event.profileId
            countView()
            Task { await loadHostCard(detail.event.profileId) }
        case .loading:
            isEventLoading = event == nil
        case let .error(error):
            isEventLoading = false
            if event == nil { eventError = error }
        }
    }

    private func applyRoster(_ response: QueryResponse<RosterPage>) {
        switch response {
        case let .data(page):
            isRosterLoading = false
            rosterError = nil
            rosterReady = true
            registrations = page.items
            rosterTotal = page.total
            myRegistration = myRegistrationIn(page.items)
        case .loading:
            isRosterLoading = !rosterReady
        case let .error(error):
            isRosterLoading = false
            if !rosterReady { rosterError = error }
        }
    }

    private func myRegistrationIn(_ items: [any SportRegistration]) -> (any SportRegistration)? {
        guard let me = profileStore.current.value?.profileId else { return nil }
        return items.first { $0.profileId == me }
    }

    /** 每次打开详情算一次浏览；主办自己看不算（Android `maybeIncrementView`）。 */
    private func countView() {
        guard !viewCounted, !isHost else { return }
        viewCounted = true
        let service = service
        let eventId = eventId
        Task { await service.recordView(eventId: eventId) }
    }

    /** 主办的名字和头像只是装饰：拿不到就显示 id 前 8 位。 */
    private func loadHostCard(_ hostProfileId: String) async {
        guard !hostProfileId.isEmpty, loadedHostProfileId != hostProfileId || hostDisplayName == nil else { return }
        loadedHostProfileId = hostProfileId
        do {
            let card = try await authQueries.publicCards.get(hostProfileId)
            hostDisplayName = card.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(hostProfileId.prefix(8))
            hostAvatarImageId = card.avatarImageId
        } catch {
            hostDisplayName = hostDisplayName ?? String(hostProfileId.prefix(8))
        }
    }

    /* ------------------------------ 操作 ------------------------------ */

    /**
     * [payChoice] 只在 [offersPayChoice] 时有意义；只收刷卡的活动总是刷卡。[playerNote] 是给发起人的备注（最多 200 字）。
     * 成功后：要付款就弹付款面板，否则换成成功弹层。
     */
    func join(waitlistHoursBeforeStart: Int? = nil, payChoice: RegistrationPayChoice = .card, playerNote: String? = nil) async {
        let paysByCard = event?.isFree == false && acceptsStripe && (!offersPayChoice || payChoice == .card)
        let note = playerNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = await runAction {
            let result = try await self.service.join(
                eventId: self.eventId,
                waitlistHoursBeforeStart: waitlistHoursBeforeStart,
                playerNote: note?.isEmpty == false ? note : nil,
                payByCard: paysByCard
            )
            self.apply(result.registration)
            if let payment = result.payment {
                self.paymentSession = payment
                self.paidPending = false
            }
        }
        guard joined, sheet == .join || sheet == .waitlist else { return }
        if paymentSession != nil {
            sheet = nil
        } else {
            sheet = sheet == .join ? .joinSuccess : .waitlistSuccess
        }
    }

    func rejoin() async {
        await join()
    }

    /** 重新拿占座付款会话并弹出付款面板。 */
    func openPayment() async {
        guard !isPaymentLoading else { return }
        isPaymentLoading = true
        defer { isPaymentLoading = false }
        do {
            paymentSession = try await service.myRegistrationPayment(eventId: eventId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payments_hold_load_failed")
        }
    }

    func pay(_ paymentMethodId: String) async throws -> PaymentAttempt {
        try await service.payMyRegistration(eventId: eventId, paymentMethodId: paymentMethodId)
    }

    func onPaid() {
        paymentSession = nil
        paidPending = true
        service.invalidate()
    }

    func exit() async {
        let done = await runAction {
            let registration = try await self.service.exitEvent(eventId: self.eventId)
            self.apply(registration)
        }
        if done { sheet = nil }
    }

    func endEvent() async {
        _ = await runAction { try await self.service.endEvent(eventId: self.eventId) }
    }

    /** [payeePaymentAccountId] 为 nil 表示不收刷卡；和当前一样时不发这个字段。 */
    func patchBasic(title: String, venueName: String, description: String, payeePaymentAccountId: String?) async {
        let current = event?.payeePaymentAccountId
        let payee: PayeePatch = payeePaymentAccountId == current ? .unchanged : payeePaymentAccountId.map(PayeePatch.account) ?? .none
        _ = await runAction {
            try await self.service.patchBasic(eventId: self.eventId, title: title, venueName: venueName, description: description, payee: payee)
        }
    }

    func closeSheet() {
        guard !isActionInProgress else { return }
        sheet = nil
        actionError = nil
    }

    /** 报名 / 退出后的那条报名立即替换名单里的我（不用等重拉）。 */
    private func apply(_ registration: any SportRegistration) {
        if let index = registrations.firstIndex(where: { $0.id == registration.id }) {
            registrations[index] = registration
        } else {
            registrations.append(registration)
        }
        myRegistration = registration
    }

    /** 一次只跑一个操作；失败写进 [actionError]（弹层里显示），返回是否成功。 */
    private func runAction(_ block: @escaping @MainActor () async throws -> Void) async -> Bool {
        guard !isActionInProgress else { return false }
        isActionInProgress = true
        actionError = nil
        defer { isActionInProgress = false }
        do {
            try await block()
            return true
        } catch {
            actionError = UiError(error).text(fallback: String(localized: "event_detail_action_failed"))
            return false
        }
    }
}
