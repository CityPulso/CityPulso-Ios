import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 确认订场（Android `<Sport>VenueConfirmViewModel`，三种运动共用）：选好的几段、订场方式（有能付的时长包时默认用包）、
 * 联系信息和备注，提交后进这条订场的详情。请求体不变时复用同一个幂等键，连点不会生成第二笔预订。
 */
@MainActor
@Observable
final class VenueConfirmModel {
    static let contactNameMax = 120
    static let contactPhoneMax = 40
    static let noteMax = 500

    let venueId: String
    let sport: VenueSport
    let dateKey: String

    private(set) var venue = Loadable<VenueDetail>()
    private(set) var entry = Loadable<CourtEntryUi>()
    private(set) var day = Loadable<CourtDayUi>()
    private(set) var selection: BoardSelection
    /** 用户手选的方式 / 时长包；没选或已经失效时用 [method] / [bundleId] 推出的默认值。 */
    private(set) var pickedMethod: CourtBookingPaymentMethod?
    private(set) var pickedBundleId: String?
    /** 我在这家球馆能付这项运动订场的时长包（没登录为空）。 */
    private(set) var usableBundles: [MyBundle] = []
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
    @ObservationIgnored @Injected(\.bundleService) private var bundleService
    @ObservationIgnored @Injected(\.membershipService) private var membershipService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let service: any VenueSportService

    init(venueId: String, sport: VenueSport, dateKey: String, ranges: [VenueConfirmRange]) {
        self.venueId = venueId
        self.sport = sport
        self.dateKey = dateKey
        selection = BoardSelection(ranges: ranges)
        service = Container.shared.venueSportServices()[sport]!
    }

    /* ------------------------------ 派生 ------------------------------ */

    var lines: [CourtLineUi] { selection.lines(day.data) }
    var totalCents: Int { lines.reduce(0) { $0 + $1.priceCents } }
    var totalMinutes: Int { lines.reduce(0) { $0 + $1.minutes } }
    var selectionError: BookingSelectionError? {
        entry.data.flatMap { validateCourtSelection(lines, minBookingMinutes: $0.minBookingMinutes, maxBookingMinutes: $0.maxBookingMinutes) }
    }

    /** 有能用的时长包时，「时长包」放最前（WEB `CheckoutPanel`）。 */
    var methods: [CourtBookingPaymentMethod] {
        (usableBundles.isEmpty ? [] : [.bundle]) + (venue.data?.acceptedMethods ?? [])
    }

    /** 余额够付这次全部分钟的时长包。 */
    var payableBundles: [MyBundle] { usableBundles.filter { $0.canPayBooking(sport, minutes: totalMinutes) } }

    /** 有能付的时长包时默认用包，否则用球馆的第一种方式。 */
    var method: CourtBookingPaymentMethod? {
        if let pickedMethod, methods.contains(pickedMethod) { return pickedMethod }
        return payableBundles.isEmpty ? methods.first { $0 != .bundle } : .bundle
    }

    var bundleId: String? {
        if let pickedBundleId, payableBundles.contains(where: { $0.id == pickedBundleId }) { return pickedBundleId }
        return payableBundles.first?.id
    }

    var selectedBundle: MyBundle? { payableBundles.first { $0.id == bundleId } }

    /** 有效会员付折后价；时长包按原价扣，不叠加会员折扣。 */
    var pricing: CourtCheckoutPricing {
        CourtCheckoutPricing(
            linePriceCents: lines.map(\.priceCents),
            membership: myMembership.data?.membership,
            payWithBundle: method == .bundle,
            hasBundle: selectedBundle != nil
        )
    }

    var upsellLevel: MembershipLevel? { bestUpsellLevel(offers.data, membership: myMembership.data?.membership) }
    var memberSaveCents: Int { upsellSaveCents(upsellLevel, totalCents: totalCents) }
    var isPublished: Bool { entry.data.map { $0.status == .published && $0.venueStatus == .published } ?? false }
    /** 选的时段已经不能订了。 */
    var stale: Bool { !day.isLoading && (lines.isEmpty || selectionError != nil) }
    var canSubmit: Bool {
        signedIn && isPulser && isPublished && !lines.isEmpty && selectionError == nil && method != nil && !submitting
            && (method != .bundle || bundleId != nil)
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
                    self.usableBundles = []
                    self.myMembership = Loadable(isLoading: signedIn)
                    guard signedIn else {
                        signedInTask = Task {}
                        continue
                    }
                    let usable = self.bundleService.streamUsable(self.venueId, sport: self.sport)
                    let mine = self.membershipService.streamMine(self.venueId)
                    signedInTask = Task {
                        await concurrently([
                            {
                                for await response in usable {
                                    if case let .data(bundles) = response { self.usableBundles = bundles }
                                }
                            },
                            {
                                for await response in mine {
                                    self.myMembership = self.myMembership.reduce(response)
                                }
                            },
                        ])
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
            {
                for await response in self.service.entry(venueId: self.venueId) {
                    self.entry = self.entry.reduce(response)
                }
            },
            {
                for await response in self.service.availability(venueId: self.venueId, date: self.dateKey) {
                    self.day = self.day.reduce(response)
                    if let data = self.day.data { self.selection = self.selection.pruned(data) }
                }
            },
        ])
    }

    /* ------------------------------ 操作 ------------------------------ */

    func refresh() {
        venueService.invalidate()
    }

    func selectMethod(_ next: CourtBookingPaymentMethod) {
        pickedMethod = next
    }

    func selectBundle(_ id: String) {
        pickedMethod = .bundle
        pickedBundleId = id
    }

    /** 提交成功返回这条订场的详情路由。 */
    func submit() async -> LoopRoute? {
        guard canSubmit, let method else { return nil }
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundle = method == .bundle ? bundleId : nil
        let input = CourtCheckoutInput(
            paymentMethod: method,
            lines: lines,
            contactName: name.isEmpty ? nil : name,
            contactPhone: phone.isEmpty ? nil : phone,
            note: note.isEmpty ? nil : note,
            bundleId: bundle
        )
        let signature = [method.rawValue, name, phone, note, bundle ?? ""].joined(separator: "|") + lines.map(\.id).joined(separator: ",")
        let key = idempotency.flatMap { $0.signature == signature ? $0.key : nil } ?? UUID().uuidString
        idempotency = (signature, key)
        submitting = true
        defer { submitting = false }
        do {
            let result = try await service.checkout(venueId: venueId, input, idempotencyKey: key)
            idempotency = nil
            return .courtBooking(sport: sport, bookingId: result.bookingId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "venue_confirm_checkout_failed")
            venueService.invalidate()
            return nil
        }
    }
}
