import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 确认预约（Android `<ActivityType>VenueConfirmViewModel`，按桌台订的类型共用）：选好的几段、付款方式、
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

    private(set) var venue = Loadable<VenueDetail>()
    private(set) var entry = Loadable<SpaceEntryUi>()
    private(set) var day = Loadable<SpaceDayUi>()
    private(set) var selection: BoardSelection
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
    @ObservationIgnored private let service: any VenueActivityTypeService

    init(venueId: String, activityType: VenueActivityType, dateKey: String, ranges: [VenueConfirmRange]) {
        self.venueId = venueId
        self.activityType = activityType
        self.dateKey = dateKey
        selection = BoardSelection(ranges: ranges)
        service = Container.shared.venueActivityTypeServices()[activityType]!
    }

    /* ------------------------------ 派生 ------------------------------ */

    var lines: [SpaceLineUi] { selection.lines(day.data) }
    var totalCents: Int { lines.reduce(0) { $0 + $1.priceCents } }
    var selectionError: BookingSelectionError? {
        entry.data.flatMap { validateSpaceSelection(lines, minBookingMinutes: $0.minBookingMinutes, maxBookingMinutes: $0.maxBookingMinutes) }
    }

    var methods: [SpaceBookingPaymentMethod] { venue.data?.acceptedMethods ?? [] }

    var method: SpaceBookingPaymentMethod? {
        if let pickedMethod, methods.contains(pickedMethod) { return pickedMethod }
        return methods.first
    }

    /** 有效会员付折后价。 */
    var pricing: SpaceCheckoutPricing { SpaceCheckoutPricing(linePriceCents: lines.map(\.priceCents), membership: myMembership.data?.membership) }

    var upsellLevel: MembershipLevel? { bestUpsellLevel(offers.data, membership: myMembership.data?.membership) }
    var memberSaveCents: Int { upsellSaveCents(upsellLevel, totalCents: totalCents) }
    var isPublished: Bool { entry.data.map { $0.status == .published && $0.venueStatus == .published } ?? false }
    /** 选的时段已经不能订了。 */
    var stale: Bool { !day.isLoading && (lines.isEmpty || selectionError != nil) }
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

    func selectMethod(_ next: SpaceBookingPaymentMethod) {
        pickedMethod = next
    }

    /** 提交成功返回这条预约的详情路由。 */
    func submit() async -> NearRoute? {
        guard canSubmit, let method else { return nil }
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = SpaceCheckoutInput(
            paymentMethod: method,
            lines: lines,
            contactName: name.isEmpty ? nil : name,
            contactPhone: phone.isEmpty ? nil : phone,
            note: note.isEmpty ? nil : note
        )
        let signature = [method.rawValue, name, phone, note].joined(separator: "|") + lines.map(\.id).joined(separator: ",")
        let key = idempotency.flatMap { $0.signature == signature ? $0.key : nil } ?? UUID().uuidString
        idempotency = (signature, key)
        submitting = true
        defer { submitting = false }
        do {
            let result = try await service.checkout(venueId: venueId, input, idempotencyKey: key)
            idempotency = nil
            return .spaceBooking(activityType: activityType, bookingId: result.bookingId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "venue_confirm_checkout_failed")
            venueService.invalidate()
            return nil
        }
    }
}
