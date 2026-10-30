import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 确认预约（Android `<ActivityType>VenueConfirmViewModel`，所有门店类型共用）：选好的几段桌台或一场主题 / 剧本、付款方式、
 * 联系信息和备注，提交后进这条预约的详情。请求体不变时复用同一个幂等键，连点不会生成第二笔预订。
 */
@MainActor
@Observable
final class VenueConfirmModel {
    static let contactNameMax = 120
    static let contactPhoneMax = 40
    static let noteMax = 500

    let venueId: String
    let activityType: VenueActivityType
    let dateKey: String

    let target: VenueConfirmTarget

    private(set) var venue = Loadable<VenueDetail>()
    /** 按桌台订：规则、当天的表和选好的格子。 */
    private(set) var entry = Loadable<SpaceEntryUi>()
    private(set) var day = Loadable<SpaceDayUi>()
    private(set) var selection: BoardSelection = [:]
    /** 按场次订：规则、主题 / 剧本和当天的场次。 */
    private(set) var sessionEntry = Loadable<SessionEntryUi>()
    private(set) var options = Loadable<[SessionOptionUi]>()
    private(set) var sessionDay = Loadable<SessionDayUi>()
    /** 用户手选的方式；没选或已经失效时用门店的第一种。 */
    private(set) var pickedMethod: SpaceBookingPaymentMethod?
    var contactName = "" {
        didSet {
            if contactName.count > Self.contactNameMax { contactName = String(contactName.prefix(Self.contactNameMax)) }
            contactNameEdited = true
        }
    }

    var contactPhone = "" {
        didSet {
            if contactPhone.count > Self.contactPhoneMax { contactPhone = String(contactPhone.prefix(Self.contactPhoneMax)) }
            contactPhoneEdited = true
        }
    }

    var note = "" { didSet { if note.count > Self.noteMax { note = String(note.prefix(Self.noteMax)) } } }
    private(set) var submitting = false
    private(set) var isPulser = false
    private(set) var signedIn = false
    private(set) var offers = Loadable<MembershipOffersGrid>()
    private(set) var myMembership = Loadable<MyVenueMembership>(isLoading: false)

    /** 用户改过以后，资料更新不再覆盖。 */
    @ObservationIgnored private var contactNameEdited = false
    @ObservationIgnored private var contactPhoneEdited = false
    @ObservationIgnored private var idempotency: (signature: String, key: String)?

    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.membershipService) private var membershipService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let spaceServices = Container.shared.venueActivityTypeServices()
    @ObservationIgnored private let sessionServices = Container.shared.sessionVenueServices()

    init(venueId: String, activityType: VenueActivityType, dateKey: String, target: VenueConfirmTarget) {
        self.venueId = venueId
        self.activityType = activityType
        self.dateKey = dateKey
        self.target = target
        if case let .spaces(ranges) = target { selection = BoardSelection(ranges: ranges) }
    }

    /* ------------------------------ 派生 ------------------------------ */

    private var sessionPick: VenueSessionPick? {
        if case let .session(pick) = target { pick } else { nil }
    }

    /** 选的主题 / 剧本。 */
    private var option: SessionOptionUi? { sessionPick.flatMap { pick in options.data?.first { $0.id == pick.optionId } } }

    /** 最新场次表里还空着的那一场；被订走或没了是 nil。 */
    private var sessionSlot: SessionSlotUi? {
        sessionPick.flatMap { pick in sessionDay.data?.rows.first { $0.optionId == pick.optionId }?.slots.first { $0.startsAt == pick.startsAt && $0.available } }
    }

    /** 按场次订时的人数，夹在主题 / 剧本的人数范围里。 */
    var partySize: Int? {
        guard let pick = sessionPick else { return nil }
        return option.map { min(max(pick.partySize, $0.playersMin), $0.playersMax) } ?? pick.partySize
    }

    var lines: [SpaceLineUi] {
        switch target {
        case .spaces:
            return selection.lines(day.data)
        case .session:
            guard let option, let slot = sessionSlot, let partySize else { return [] }
            let cents = sessionPriceCents(slot.priceCents, extraPlayerAmount: option.extraPlayerAmount, playersMin: option.playersMin, partySize: partySize)
            return [SpaceLineUi(spaceId: option.id, spaceName: option.name, startsAt: slot.startsAt, endsAt: slot.endsAt, minutes: option.durationMinutes, priceCents: cents)]
        }
    }

    var totalCents: Int { lines.reduce(0) { $0 + $1.priceCents } }
    var selectionError: BookingSelectionError? {
        guard case .spaces = target else { return nil }
        return entry.data.flatMap { validateSpaceSelection(lines, minBookingMinutes: $0.minBookingMinutes, maxBookingMinutes: $0.maxBookingMinutes) }
    }

    /** 当天的表还在第一次加载。 */
    var dayLoading: Bool {
        switch target {
        case .spaces: day.isLoading
        case .session: sessionDay.isLoading || options.isLoading
        }
    }

    var dayError: UiError? {
        switch target {
        case .spaces: day.error
        case .session: sessionDay.error ?? options.error
        }
    }

    var refundPolicy: (policy: SpaceRefundPolicy, tiers: [SpaceRefundTierUi], note: String?)? {
        if let entry = entry.data { return (entry.refundPolicy, entry.refundTiers, entry.refundPolicyNote) }
        if let entry = sessionEntry.data { return (entry.refundPolicy, entry.refundTiers, entry.refundPolicyNote) }
        return nil
    }

    /** 规则已经读到（用来决定是否提示「未上线」）。 */
    var entryLoaded: Bool { entry.data != nil || sessionEntry.data != nil }

    var methods: [SpaceBookingPaymentMethod] { venue.data?.acceptedMethods ?? [] }

    var method: SpaceBookingPaymentMethod? {
        if let pickedMethod, methods.contains(pickedMethod) { return pickedMethod }
        return methods.first
    }

    /** 有效会员付折后价。 */
    var pricing: SpaceCheckoutPricing { SpaceCheckoutPricing(linePriceCents: lines.map(\.priceCents), membership: myMembership.data?.membership) }

    var upsellLevel: MembershipLevel? { bestUpsellLevel(offers.data, membership: myMembership.data?.membership) }
    var memberSaveCents: Int { upsellSaveCents(upsellLevel, totalCents: totalCents) }
    var isPublished: Bool {
        if let entry = entry.data { return entry.status == .published && entry.venueStatus == .published }
        if let entry = sessionEntry.data { return entry.status == .published && entry.venueStatus == .published }
        return false
    }

    /** 选的时段已经不能订了。 */
    var stale: Bool { !dayLoading && (lines.isEmpty || selectionError != nil) }
    var canSubmit: Bool {
        signedIn && isPulser && isPublished && !lines.isEmpty && selectionError == nil && method != nil && !submitting
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /* ------------------------------ 订阅 ------------------------------ */

    func observe() async {
        await concurrently([
            {
                // 联系人默认用账号全名（没有就用显示名）和主电话（WEB CheckoutPanel）；用户改过的字段不再覆盖。
                for await info in self.profileStore.current.values() {
                    self.isPulser = info?.isPulser == true
                    guard let info else { continue }
                    if !self.contactNameEdited {
                        self.contactName = String((info.fullName ?? info.displayName ?? "").prefix(Self.contactNameMax))
                        self.contactNameEdited = false
                    }
                    if !self.contactPhoneEdited {
                        self.contactPhone = String((info.primaryPhone ?? "").prefix(Self.contactPhoneMax))
                        self.contactPhoneEdited = false
                    }
                }
            },
            {
                var signedInTask: Task<Void, Never>?
                for await session in self.sessionStore.state.values() {
                    let signedIn = session.isAuthValid && !session.currentProfileId.isEmpty
                    guard signedIn != self.signedIn || signedInTask == nil else { continue }
                    self.signedIn = signedIn
                    signedInTask?.cancel()
                    self.myMembership = Loadable(isLoading: signedIn)
                    guard signedIn else {
                        signedInTask = Task {}
                        continue
                    }
                    let mine = self.membershipService.streamMine(self.venueId)
                    signedInTask = Task {
                        for await response in mine {
                            self.myMembership = self.myMembership.reduce(response)
                        }
                    }
                }
                signedInTask?.cancel()
            },
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
        ] + targetStreams)
    }

    /** 桌台：规则和当天的表（重拉后去掉不能订的格子）；场次：规则、主题 / 剧本和当天的场次。 */
    private var targetStreams: [@MainActor () async -> Void] {
        let venueId = venueId
        let dateKey = dateKey
        if let service = spaceServices[activityType] {
            return [
                {
                    for await response in service.entry(venueId: venueId) {
                        self.entry = self.entry.reduce(response)
                    }
                },
                {
                    for await response in service.availability(venueId: venueId, date: dateKey) {
                        self.day = self.day.reduce(response)
                        if let data = self.day.data { self.selection = self.selection.pruned(data) }
                    }
                },
            ]
        }
        guard let service = sessionServices[activityType] else { return [] }
        return [
            {
                for await response in service.entry(venueId: venueId) {
                    self.sessionEntry = self.sessionEntry.reduce(response)
                }
            },
            {
                for await response in service.options(venueId: venueId) {
                    self.options = self.options.reduce(response)
                }
            },
            {
                for await response in service.availability(venueId: venueId, date: dateKey) {
                    self.sessionDay = self.sessionDay.reduce(response)
                }
            },
        ]
    }

    /* ------------------------------ 操作 ------------------------------ */

    func refresh() {
        venueService.invalidate()
    }

    func selectMethod(_ next: SpaceBookingPaymentMethod) {
        pickedMethod = next
    }

    /** 提交成功返回这条预约的详情路由。 */
    func submit() async -> NearRoute? {
        guard canSubmit, let method else { return nil }
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = (name: name.isEmpty ? nil : name, phone: phone.isEmpty ? nil : phone, note: note.isEmpty ? nil : note)
        let signature = [method.rawValue, name, phone, note, partySize.map(String.init) ?? ""].joined(separator: "|") + lines.map(\.id).joined(separator: ",")
        let key = idempotency.flatMap { $0.signature == signature ? $0.key : nil } ?? UUID().uuidString
        idempotency = (signature, key)
        submitting = true
        defer { submitting = false }
        do {
            let result: SpaceCheckoutResultUi
            switch target {
            case .spaces:
                let input = SpaceCheckoutInput(paymentMethod: method, lines: lines, contactName: contact.name, contactPhone: contact.phone, note: contact.note)
                result = try await spaceServices[activityType]!.checkout(venueId: venueId, input, idempotencyKey: key)
            case let .session(pick):
                let input = SessionCheckoutInput(
                    paymentMethod: method,
                    optionId: pick.optionId,
                    startsAt: pick.startsAt,
                    partySize: partySize ?? pick.partySize,
                    contactName: contact.name,
                    contactPhone: contact.phone,
                    note: contact.note
                )
                result = try await sessionServices[activityType]!.checkout(venueId: venueId, input, idempotencyKey: key)
            }
            idempotency = nil
            return .spaceBooking(activityType: activityType, bookingId: result.bookingId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "venue_confirm_checkout_failed")
            venueService.invalidate()
            return nil
        }
    }
}

/** 确认页要订的：几段桌台，或一场主题 / 剧本。 */
enum VenueConfirmTarget: Hashable, Sendable {
    case spaces([VenueConfirmRange])
    case session(VenueSessionPick)
}
