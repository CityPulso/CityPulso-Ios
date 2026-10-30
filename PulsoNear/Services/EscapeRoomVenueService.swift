/* 密室逃脱按场次订（Android `VenueBookingTemplate.SESSION`），和桌台类不同，所以手写，不从桌游分叉。 */

import Foundation
import PulsoLinkCore

/**
 * 门店密室逃脱入口的读缓存（Android `VenueQueryStore` 里密室逃脱那几项）：规则、主题、某天的场次（15 秒过期）、
 * 我的订场。任何门店写操作（[VenueEventBus]）全部失效。
 */
final class EscapeRoomVenueQueryStore: LogoutClearable {
    let entry: MemoryQuery<VenueKey, EscapeRoomEntry>
    let options: MemoryQuery<VenueKey, [EscapeRoomTheme]>
    let availability: MemoryQuery<VenueAvailabilityKey, EscapeRoomDayGrid>
    let myBookings: MemoryQuery<MySpaceBookingsKey, ListWithTotal<EscapeRoomMySpaceBooking>>
    let myBooking: MemoryQuery<String, EscapeRoomMySpaceBooking>

    init(api: EscapeRoomEntryAPI, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        entry = MemoryQuery(invalidates: invalidates) { key in try await api.getEntry(venueId: key.venueId).dataOrThrow("GetEscapeRoomEntry") }
        options = MemoryQuery(invalidates: invalidates) { key in try await api.listThemes(venueId: key.venueId).dataOrThrow("ListEscapeRoomThemes") }
        availability = MemoryQuery(ttl: .seconds(15), invalidates: invalidates) { key in
            try await api.getAvailability(venueId: key.venueId, date: key.date).dataOrThrow("GetEscapeRoomAvailability")
        }
        myBookings = MemoryQuery(invalidates: invalidates) { key in
            try await api.listMyEscapeRoomSpaceBookings(EscapeRoomMySpaceBookingsRequest(limit: key.limit, upcoming: key.upcoming)).dataOrThrow("ListMySpaceBookings")
        }
        myBooking = MemoryQuery(invalidates: invalidates) { bookingId in
            try await api.getMyEscapeRoomSpaceBooking(bookingId: bookingId).dataOrThrow("GetMySpaceBooking")
        }
    }

    func onLogout() async throws {
        await entry.clear()
        await options.clear()
        await availability.clear()
        await myBookings.clear()
        await myBooking.clear()
    }
}

/** 门店密室逃脱入口的门面（Android `VenueService` 里密室逃脱那几项）：写操作成功后一次 [VenueEventBus.invalidate]。 */
struct EscapeRoomVenueService: SessionVenueService {
    let api: EscapeRoomEntryAPI
    let query: EscapeRoomVenueQueryStore
    let eventBus: VenueEventBus
    let session: AuthSessionStore

    var activityType: VenueActivityType { .escapeRoom }

    private var profileId: String { session.state.value.currentProfileId }

    func entry(venueId: String) -> AsyncStream<QueryResponse<SessionEntryUi>> {
        query.entry.stream(VenueKey(venueId: venueId, profileId: profileId)).mapResponses(SessionEntryUi.init)
    }

    func options(venueId: String) -> AsyncStream<QueryResponse<[SessionOptionUi]>> {
        query.options.stream(VenueKey(venueId: venueId, profileId: profileId)).mapResponses { $0.map(SessionOptionUi.init) }
    }

    func availability(venueId: String, date: String) -> AsyncStream<QueryResponse<SessionDayUi>> {
        query.availability.stream(VenueAvailabilityKey(venueId: venueId, activityType: activityType, date: date, profileId: profileId)).mapResponses(SessionDayUi.init)
    }

    func checkout(venueId: String, _ input: SessionCheckoutInput, idempotencyKey: String) async throws -> SpaceCheckoutResultUi {
        let body = EscapeRoomCheckoutRequest(
            paymentMethod: input.paymentMethod,
            session: EscapeRoomSession(themeId: input.optionId, startsAt: input.startsAt, partySize: input.partySize),
            contactName: input.contactName,
            contactPhone: input.contactPhone,
            note: input.note
        )
        let result = try await api.checkoutEscapeRoomSpaceBooking(venueId: venueId, idempotencyKey: idempotencyKey, body).dataOrThrow("CheckoutSpaceBooking")
        eventBus.invalidate()
        return SpaceCheckoutResultUi(
            bookingId: result.bookingId,
            status: result.status,
            paymentMethod: result.paymentMethod,
            totalAmount: result.totalAmount,
            currency: result.currency,
            expiresAt: result.expiresAt,
            payment: result.payment
        )
    }

    func myBookings(_ key: MySpaceBookingsKey) -> AsyncStream<QueryResponse<[SpaceBookingRowUi]>> {
        query.myBookings.stream(key).mapResponses { $0.items.map(SpaceBookingRowUi.init) }
    }

    /** 我的订场，每页 20 条；任何门店写操作都让列表重拉。 */
    @MainActor
    func pageMyBookings(upcoming: Bool) -> PagedList<SpaceBookingRowUi, Int> {
        let api = api
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            let page = try await api.listMyEscapeRoomSpaceBookings(EscapeRoomMySpaceBookingsRequest(offset: offset, limit: limit, upcoming: upcoming))
                .dataOrThrow("ListMySpaceBookings")
            return ListWithTotal(items: page.items.map(SpaceBookingRowUi.init), total: page.total)
        }
    }

    func myBooking(_ bookingId: String) -> AsyncStream<QueryResponse<MySpaceBookingUi>> {
        query.myBooking.stream(bookingId).mapResponses(MySpaceBookingUi.init)
    }

    func refetchMyBooking(_ bookingId: String) async throws -> MySpaceBookingUi {
        MySpaceBookingUi(try await query.myBooking.fresh(bookingId))
    }

    func bookingPayment(_ bookingId: String) async throws -> PaymentHoldActivity {
        try await api.getEscapeRoomSpaceBookingPayment(bookingId: bookingId).dataOrThrow("GetSpaceBookingPayment")
    }

    func payBooking(_ bookingId: String, paymentMethodId: String) async throws -> PaymentAttempt {
        let attempt = try await api.payEscapeRoomSpaceBookingPayment(bookingId: bookingId, PayPaymentRequest(paymentMethodId: paymentMethodId))
            .dataOrThrow("PaySpaceBookingPayment")
        eventBus.invalidate()
        return attempt
    }

    func refundPreview(_ bookingId: String) async throws -> SpaceRefundPreviewUi {
        let preview = try await api.getEscapeRoomSpaceBookingRefundPreview(bookingId: bookingId).dataOrThrow("GetSpaceBookingRefundPreview")
        return SpaceRefundPreviewUi(
            refundAmount: preview.refundAmount,
            totalAmount: preview.totalAmount,
            providerFeeAmount: preview.providerFeeAmount,
            currency: preview.currency,
            policy: SpaceRefundPolicy(wire: preview.policyType.rawValue),
            policyNote: preview.policyNote,
            tiers: preview.tiers.map { SpaceRefundTierUi(hoursBeforeStart: $0.hoursBeforeStart, refundPercent: $0.refundPercent) }
        )
    }

    func cancelBooking(_ bookingId: String, reason: String?) async throws {
        try await api.cancelMyEscapeRoomSpaceBooking(bookingId: bookingId, EscapeRoomCancelReasonRequest(reason: reason))
        eventBus.invalidate()
    }
}

/* ------------------------------ 密室逃脱 DTO → 活动类型无关的形状 ------------------------------ */

extension SessionEntryUi {
    init(_ entry: EscapeRoomEntry) {
        self.init(
            status: entry.status,
            bookingWindowDays: entry.bookingWindowDays,
            bookingLeadMinutes: entry.bookingLeadMinutes,
            slotMinutes: entry.slotMinutes,
            bufferMinutes: entry.bufferMinutes,
            refundPolicy: SpaceRefundPolicy(wire: entry.refundPolicyType.rawValue),
            refundPolicyNote: entry.refundPolicyNote,
            refundTiers: entry.refundTiers.map { SpaceRefundTierUi(hoursBeforeStart: $0.hoursBeforeStart, refundPercent: $0.refundPercent) },
            optionCount: entry.themeCount,
            minSessionPriceAmount: entry.minSessionPriceAmount,
            timezone: entry.timezone,
            currency: entry.currency,
            venueStatus: entry.venueStatus
        )
    }
}

extension SessionOptionUi {
    init(_ option: EscapeRoomTheme) {
        self.init(
            id: option.id,
            name: option.name,
            subtitle: option.spaceName,
            description: option.description,
            sortOrder: option.sortOrder,
            durationMinutes: option.durationMinutes,
            playersMin: option.playersMin,
            playersMax: option.playersMax,
            difficulty: option.difficulty,
            priceAmount: option.priceAmount,
            extraPlayerAmount: option.extraPlayerAmount,
            isActive: option.isActive,
            images: option.images
        )
    }
}

extension SessionDayUi {
    init(_ grid: EscapeRoomDayGrid) {
        self.init(
            date: grid.date,
            bookable: grid.bookable,
            rows: grid.themes.map { row in
                SessionRowUi(
                    optionId: row.themeId,
                    name: row.name,
                    sortOrder: row.sortOrder,
                    durationMinutes: row.durationMinutes,
                    slots: row.slots.map { SessionSlotUi(startsAt: $0.startsAt, endsAt: $0.endsAt, available: $0.status == .available, priceCents: $0.priceCents) }
                )
            }
        )
    }
}

extension MySpaceBookingUi {
    init(_ booking: EscapeRoomMySpaceBooking) {
        self.init(
            id: booking.id,
            activityType: .escapeRoom,
            venueId: booking.venueId,
            mode: .scheduled, // 场次没有到店开台
            status: booking.status,
            paymentMethod: booking.paymentMethod,
            startsAt: booking.startsAt,
            endsAt: booking.endsAt,
            totalAmount: booking.totalAmount,
            currency: booking.currency,
            refundAmount: booking.refundAmount,
            refundStatus: booking.refundStatus?.rawValue,
            contactName: booking.contactName,
            contactPhone: booking.contactPhone,
            note: booking.note,
            expiresAt: booking.expiresAt,
            confirmedAt: booking.confirmedAt,
            canceledAt: booking.canceledAt,
            canceledBy: booking.canceledBy,
            cancelReason: booking.cancelReason,
            expiredAt: booking.expiredAt,
            paidMarkedAt: booking.paidMarkedAt,
            paymentId: booking.paymentId,
            createdAt: booking.createdAt,
            slots: booking.slots.map {
                SpaceBookingSlotUi(id: $0.id, spaceId: $0.spaceId, spaceName: $0.spaceName, startsAt: $0.startsAt, endsAt: $0.endsAt, priceAmount: $0.priceAmount, holdsSlot: $0.holdsSlot)
            },
            priceBreakdown: booking.priceBreakdown.map {
                SpacePriceLineUi(spaceId: $0.spaceId, startsAt: $0.startsAt, endsAt: $0.endsAt, amount: $0.amount, rateLabel: $0.rateLabel)
            },
            refundPolicy: SpaceRefundPolicy(wire: booking.refundPolicySnapshot.type.rawValue),
            refundPolicyNote: booking.refundPolicySnapshot.note,
            refundTiers: booking.refundPolicySnapshot.tiers.map { SpaceRefundTierUi(hoursBeforeStart: $0.hoursBeforeStart, refundPercent: $0.refundPercent) },
            venueName: booking.venueName,
            venueAddress: booking.venueAddress,
            venuePhone: booking.venuePhone,
            venueTimezone: booking.venueTimezone,
            venueLocationLat: booking.venueLocationLat,
            venueLocationLng: booking.venueLocationLng,
            venueBookingInstructions: booking.venueBookingInstructions,
            venueCoverImageId: booking.venueCoverImageId
        )
    }
}

extension SpaceBookingRowUi {
    init(_ booking: EscapeRoomMySpaceBooking) {
        self.init(
            id: booking.id, venueName: booking.venueName, venueAddress: booking.venueAddress, venueCoverImageId: booking.venueCoverImageId,
            venueTimezone: booking.venueTimezone, startsAt: booking.startsAt, endsAt: booking.endsAt, status: booking.status,
            expiresAt: booking.expiresAt, spaceCount: Set(booking.slots.map(\.spaceId)).count, totalAmount: booking.totalAmount, currency: booking.currency,
            spaceNames: booking.slots.map(\.spaceName).filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        )
    }
}
