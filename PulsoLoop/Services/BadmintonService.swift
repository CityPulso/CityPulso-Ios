import PulsoLinkCore

/**
 * Loop 羽毛球门面（对应 Android `BadmintonService`、WEB `hooks/badminton.ts`）：
 * 读走 [BadmintonQueryStore]；写成功后一次 [BadmintonEventBus.invalidate]。
 */
struct BadmintonService: Sendable {
    let repository: BadmintonRepository
    let query: BadmintonQueryStore
    let eventBus: BadmintonEventBus
    let exploreQuery: ExploreQueryStore

    static let rosterPageSize = BadmintonQueryStore.rosterPageSize

    /** 我主持的活动的收款清单，分页；这个运动的任何写操作都会让它重拉。 */
    @MainActor
    func pageHostedChecklists(isAllSettled: Bool) -> PagedList<HostedChecklistRowUi, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            let page = try await repository.listHostedPaymentChecklists(
                BadmintonListHostedPaymentChecklistsRequest(offset: offset, limit: limit, isAllSettled: isAllSettled)
            )
            return ListWithTotal(items: page.items.map(HostedChecklistRowUi.init), total: page.total)
        }
    }

    /** 我自己欠的收款行，分页。 */
    @MainActor
    func pageMyPaymentItems(paid: Bool) -> PagedList<MyChecklistItemRowUi, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            let page = try await repository.listMyPaymentChecklistItems(
                BadmintonListMyPaymentChecklistItemsRequest(offset: offset, limit: limit, paid: paid)
            )
            return ListWithTotal(items: page.items.map(MyChecklistItemRowUi.init), total: page.total)
        }
    }

    func prefetchDetail(eventId: String) {
        query.prefetchDetail(eventId: eventId)
    }

    func incrementView(eventId: String) async throws -> IncrementBadmintonEventViewResponse {
        let response = try await repository.incrementBadmintonEventView(eventId: eventId)
        await query.overlayView(eventId: eventId, view: response.view)
        await exploreQuery.overlayView(eventId: eventId, view: response.view)
        return response
    }

    func create(_ body: CreateBadmintonEventRequest) async throws -> CreateBadmintonEventResponse {
        let response = try await repository.createBadmintonEvent(body)
        eventBus.invalidate()
        return response
    }

    func join(eventId: String, _ body: JoinBadmintonEventRequest = JoinBadmintonEventRequest()) async throws -> JoinBadmintonEventResponse {
        let response = try await repository.joinBadmintonEvent(eventId: eventId, body)
        eventBus.invalidate()
        return response
    }

    func getMyRegistrationPayment(eventId: String) async throws -> PaymentHoldSession {
        try await repository.getMyRegistrationPayment(eventId: eventId)
    }

    func payMyRegistrationPayment(eventId: String, paymentMethodId: String) async throws -> PaymentAttempt {
        let attempt = try await repository.payMyRegistrationPayment(eventId: eventId, PayPaymentRequest(paymentMethodId: paymentMethodId))
        invalidate()
        return attempt
    }

    /** Stripe 付款成功后 webhook 才改报名状态，让订阅方重拉。 */
    func invalidate() {
        eventBus.invalidate()
    }

    func exit(eventId: String) async throws -> BadmintonRegistration {
        let registration = try await repository.exitBadmintonEvent(eventId: eventId)
        eventBus.invalidate()
        return registration
    }

    func end(eventId: String) async throws {
        try await repository.endBadmintonEvent(eventId: eventId)
        eventBus.invalidate()
    }

    func patchBasic(eventId: String, _ body: PatchBadmintonEventBasicRequest) async throws {
        try await repository.patchBadmintonEventBasic(eventId: eventId, body)
        eventBus.invalidate()
    }

    func markPaymentItemPaid(itemId: String) async throws {
        try await repository.markPaymentChecklistItemPaid(itemId: itemId)
        eventBus.invalidate()
    }

    func markPaymentItemUnpaid(itemId: String) async throws {
        try await repository.markPaymentChecklistItemUnpaid(itemId: itemId)
        eventBus.invalidate()
    }

    func settleAll(eventId: String) async throws -> BadmintonPaymentChecklistResponse {
        let response = try await repository.settleAllPaymentChecklist(eventId: eventId)
        eventBus.invalidate()
        return response
    }

    func remindItems(eventId: String, itemIds: [String]) async throws {
        try await repository.remindPaymentChecklistItems(eventId: eventId, itemIds: itemIds)
        eventBus.invalidate()
    }
}

extension HostedChecklistRowUi {
    init(_ item: BadmintonHostedPaymentChecklistItem) {
        self.init(
            checklistId: item.id,
            eventId: item.badmintonEventId,
            title: item.title.isEmpty ? String(item.badmintonEventId.prefix(8)) : item.title,
            venueName: item.venueName ?? item.address,
            startsAt: item.startsAt,
            isAllSettled: item.isAllSettled
        )
    }
}

extension MyChecklistItemRowUi {
    init(_ item: BadmintonMyPaymentChecklistItem) {
        self.init(
            itemId: item.id,
            eventId: item.badmintonEventId,
            title: item.title.isEmpty ? String(item.badmintonEventId.prefix(8)) : item.title,
            venueName: item.venueName ?? item.address,
            startsAt: item.startsAt,
            paid: item.paid,
            priceAmount: item.priceAmount,
            currency: item.currency
        )
    }
}
