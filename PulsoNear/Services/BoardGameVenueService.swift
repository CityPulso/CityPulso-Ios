import Foundation
import PulsoLinkCore

/**
 * 门店桌游入口的读缓存（Android `VenueQueryStore` 里桌游那几项）：规则、场地、价格方案、某天的可用性（15 秒过期）、
 * 我的订场。任何门店写操作（[VenueEventBus]）全部失效。
 */
final class BoardGameVenueQueryStore: LogoutClearable {
    let entry: MemoryQuery<VenueKey, BoardGameEntry>
    let spaces: MemoryQuery<VenueKey, [BoardGameSpace]>
    let ratePlans: MemoryQuery<VenueKey, [BoardGameRatePlan]>
    let availability: MemoryQuery<VenueAvailabilityKey, BoardGameDayGrid>
    let myBookings: MemoryQuery<MySpaceBookingsKey, ListWithTotal<BoardGameMySpaceBooking>>
    let myBooking: MemoryQuery<String, BoardGameMySpaceBooking>

    init(api: BoardGameEntryAPI, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        entry = MemoryQuery(invalidates: invalidates) { key in try await api.getEntry(venueId: key.venueId).dataOrThrow("GetBoardGameEntry") }
        spaces = MemoryQuery(invalidates: invalidates) { key in try await api.listSpaces(venueId: key.venueId).dataOrThrow("ListBoardGameSpaces") }
        ratePlans = MemoryQuery(invalidates: invalidates) { key in try await api.listRatePlans(venueId: key.venueId).dataOrThrow("ListBoardGameRatePlans") }
        availability = MemoryQuery(ttl: .seconds(15), invalidates: invalidates) { key in
            try await api.getAvailability(venueId: key.venueId, date: key.date).dataOrThrow("GetBoardGameAvailability")
        }
        myBookings = MemoryQuery(invalidates: invalidates) { key in
            try await api.listMyBoardGameSpaceBookings(BoardGameMySpaceBookingsRequest(limit: key.limit, upcoming: key.upcoming)).dataOrThrow("ListMySpaceBookings")
        }
        myBooking = MemoryQuery(invalidates: invalidates) { bookingId in
            try await api.getMyBoardGameSpaceBooking(bookingId: bookingId).dataOrThrow("GetMySpaceBooking")
        }
    }

    func onLogout() async throws {
        await entry.clear()
        await spaces.clear()
        await ratePlans.clear()
        await availability.clear()
        await myBookings.clear()
        await myBooking.clear()
    }
}

/** 门店桌游入口的门面（Android `VenueService` 里桌游那几项）：写操作成功后一次 [VenueEventBus.invalidate]。 */
struct BoardGameVenueService: VenueActivityTypeService {
    let api: BoardGameEntryAPI
    let query: BoardGameVenueQueryStore
    let eventBus: VenueEventBus
    let session: AuthSessionStore

    var activityType: VenueActivityType { .boardGame }

    private var profileId: String { session.state.value.currentProfileId }

    func entry(venueId: String) -> AsyncStream<QueryResponse<SpaceEntryUi>> {
        query.entry.stream(VenueKey(venueId: venueId, profileId: profileId)).mapResponses(SpaceEntryUi.init)
    }

    func spaces(venueId: String) -> AsyncStream<QueryResponse<[SpaceUi]>> {
        query.spaces.stream(VenueKey(venueId: venueId, profileId: profileId)).mapResponses { $0.map(SpaceUi.init) }
    }

    func ratePlans(venueId: String) -> AsyncStream<QueryResponse<[SpaceRatePlanUi]>> {
        query.ratePlans.stream(VenueKey(venueId: venueId, profileId: profileId)).mapResponses { plans in
            plans.map { SpaceRatePlanUi(id: $0.id, name: $0.name, sortOrder: $0.sortOrder, spaceIds: $0.spaceIds) }
        }
    }

    func availability(venueId: String, date: String) -> AsyncStream<QueryResponse<SpaceDayUi>> {
        query.availability.stream(VenueAvailabilityKey(venueId: venueId, activityType: activityType, date: date, profileId: profileId)).mapResponses(SpaceDayUi.init)
    }

    func checkout(venueId: String, _ input: SpaceCheckoutInput, idempotencyKey: String) async throws -> SpaceCheckoutResultUi {
        let body = BoardGameCheckoutRequest(
            paymentMethod: input.paymentMethod,
            selections: input.lines.map { BoardGameSpaceSelection(spaceId: $0.spaceId, startsAt: $0.startsAt, endsAt: $0.endsAt) },
            contactName: input.contactName,
            contactPhone: input.contactPhone,
            note: input.note
        )
        let result = try await api.checkoutBoardGameSpaceBooking(venueId: venueId, idempotencyKey: idempotencyKey, body).dataOrThrow("CheckoutSpaceBooking")
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
            let page = try await api.listMyBoardGameSpaceBookings(BoardGameMySpaceBookingsRequest(offset: offset, limit: limit, upcoming: upcoming))
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
        try await api.getBoardGameSpaceBookingPayment(bookingId: bookingId).dataOrThrow("GetSpaceBookingPayment")
    }

    func payBooking(_ bookingId: String, paymentMethodId: String) async throws -> PaymentAttempt {
        let attempt = try await api.payBoardGameSpaceBookingPayment(bookingId: bookingId, PayPaymentRequest(paymentMethodId: paymentMethodId))
            .dataOrThrow("PaySpaceBookingPayment")
        eventBus.invalidate()
        return attempt
    }

    func refundPreview(_ bookingId: String) async throws -> SpaceRefundPreviewUi {
        let preview = try await api.getBoardGameSpaceBookingRefundPreview(bookingId: bookingId).dataOrThrow("GetSpaceBookingRefundPreview")
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
        try await api.cancelMyBoardGameSpaceBooking(bookingId: bookingId, BoardGameCancelReasonRequest(reason: reason))
        eventBus.invalidate()
    }
}

/* ------------------------------ 桌游 DTO → 活动类型无关的形状 ------------------------------ */

extension SpaceEntryUi {
    init(_ entry: BoardGameEntry) {
        self.init(
            status: entry.status,
            bookingWindowDays: entry.bookingWindowDays,
            bookingLeadMinutes: entry.bookingLeadMinutes,
            slotMinutes: entry.slotMinutes,
            minBookingMinutes: entry.minBookingMinutes,
            maxBookingMinutes: entry.maxBookingMinutes,
            refundPolicy: SpaceRefundPolicy(wire: entry.refundPolicyType.rawValue),
            refundPolicyNote: entry.refundPolicyNote,
            refundTiers: entry.refundTiers.map { SpaceRefundTierUi(hoursBeforeStart: $0.hoursBeforeStart, refundPercent: $0.refundPercent) },
            spaceCount: entry.spaceCount,
            minHourlyPriceAmount: entry.minHourlyPriceAmount,
            timezone: entry.timezone,
            currency: entry.currency,
            venueStatus: entry.venueStatus
        )
    }
}

extension SpaceUi {
    init(_ space: BoardGameSpace) {
        self.init(
            id: space.id,
            name: space.name,
            sortOrder: space.sortOrder,
            kind: space.kind,
            capacityMin: space.capacityMin,
            capacityMax: space.capacityMax,
            description: space.description,
            isActive: space.isActive,
            hours: venueWeek(space.hours.map { VenueDayHours(dayOfWeek: $0.dayOfWeek, opensAt: $0.opensAt, closesAt: $0.closesAt) }),
            images: space.images
        )
    }
}

extension SpaceDayUi {
    init(_ grid: BoardGameDayGrid) {
        self.init(
            date: grid.date,
            slotMinutes: grid.slotMinutes,
            bookable: grid.bookable,
            availableCount: grid.availableCount,
            freeSpaceCount: grid.freeSpaceCount,
            spaces: grid.spaces.map { space in
                SpaceColumnUi(
                    spaceId: space.spaceId,
                    name: space.name,
                    sortOrder: space.sortOrder,
                    slots: space.slots.map {
                        SpaceSlotUi(startsAt: $0.startsAt, endsAt: $0.endsAt, status: $0.status, priceCents: $0.priceCents, rateLabel: $0.rateLabel, occupancy: $0.occupancy)
                    }
                )
            }
        )
    }
}

extension MySpaceBookingUi {
    init(_ booking: BoardGameMySpaceBooking) {
        self.init(
            id: booking.id,
            activityType: .boardGame,
            venueId: booking.venueId,
            mode: booking.mode,
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
    init(_ booking: BoardGameMySpaceBooking) {
        self.init(
            id: booking.id, venueName: booking.venueName, venueAddress: booking.venueAddress, venueCoverImageId: booking.venueCoverImageId,
            venueTimezone: booking.venueTimezone, startsAt: booking.startsAt, endsAt: booking.endsAt, status: booking.status,
            expiresAt: booking.expiresAt, spaceCount: Set(booking.slots.map(\.spaceId)).count, totalAmount: booking.totalAmount, currency: booking.currency,
            spaceNames: booking.slots.map(\.spaceName).filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        )
    }
}
