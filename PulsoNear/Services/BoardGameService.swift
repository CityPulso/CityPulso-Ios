import PulsoLinkCore

/**
 * Near 桌游门面（对应 Android `BoardGameService`、WEB `hooks/boardGame.ts`）：
 * 读走 [BoardGameQueryStore]；写成功后一次 [BoardGameEventBus.invalidate]。
 */
struct BoardGameService: Sendable {
    let repository: BoardGameRepository
    let query: BoardGameQueryStore
    let eventBus: BoardGameEventBus
    let exploreQuery: ExploreQueryStore

    static let rosterPageSize = BoardGameQueryStore.rosterPageSize

    /** 我主持的活动的收款清单，分页；这个运动的任何写操作都会让它重拉。 */
    @MainActor
    func pageHostedChecklists(isAllSettled: Bool) -> PagedList<HostedChecklistRowUi, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            let page = try await repository.listHostedPaymentChecklists(
                BoardGameListHostedPaymentChecklistsRequest(offset: offset, limit: limit, isAllSettled: isAllSettled)
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
                BoardGameListMyPaymentChecklistItemsRequest(offset: offset, limit: limit, paid: paid)
            )
            return ListWithTotal(items: page.items.map(MyChecklistItemRowUi.init), total: page.total)
        }
    }

    func prefetchDetail(activityId: String) {
        query.prefetchDetail(activityId: activityId)
    }

    func incrementView(activityId: String) async throws -> IncrementBoardGameActivityViewResponse {
        let response = try await repository.incrementBoardGameActivityView(activityId: activityId)
        await query.overlayView(activityId: activityId, view: response.view)
        await exploreQuery.overlayView(activityId: activityId, view: response.view)
        return response
    }

    func create(_ body: CreateBoardGameActivityRequest) async throws -> CreateBoardGameActivityResponse {
        let response = try await repository.createBoardGameActivity(body)
        eventBus.invalidate()
        return response
    }

    func join(activityId: String, _ body: JoinBoardGameActivityRequest = JoinBoardGameActivityRequest()) async throws -> JoinBoardGameActivityResponse {
        let response = try await repository.joinBoardGameActivity(activityId: activityId, body)
        eventBus.invalidate()
        return response
    }

    func getMyRegistrationPayment(activityId: String) async throws -> PaymentHoldActivity {
        try await repository.getMyRegistrationPayment(activityId: activityId)
    }

    func payMyRegistrationPayment(activityId: String, paymentMethodId: String) async throws -> PaymentAttempt {
        let attempt = try await repository.payMyRegistrationPayment(activityId: activityId, PayPaymentRequest(paymentMethodId: paymentMethodId))
        invalidate()
        return attempt
    }

    /** Stripe 付款成功后 webhook 才改报名状态，让订阅方重拉。 */
    func invalidate() {
        eventBus.invalidate()
    }

    func exit(activityId: String) async throws -> BoardGameRegistration {
        let registration = try await repository.exitBoardGameActivity(activityId: activityId)
        eventBus.invalidate()
        return registration
    }

    func end(activityId: String) async throws {
        try await repository.endBoardGameActivity(activityId: activityId)
        eventBus.invalidate()
    }

    func patchBasic(activityId: String, _ body: PatchBoardGameActivityBasicRequest) async throws {
        try await repository.patchBoardGameActivityBasic(activityId: activityId, body)
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

    func settleAll(activityId: String) async throws -> BoardGamePaymentChecklistResponse {
        let response = try await repository.settleAllPaymentChecklist(activityId: activityId)
        eventBus.invalidate()
        return response
    }

    func remindItems(activityId: String, itemIds: [String]) async throws {
        try await repository.remindPaymentChecklistItems(activityId: activityId, itemIds: itemIds)
        eventBus.invalidate()
    }
}

extension HostedChecklistRowUi {
    init(_ item: BoardGameHostedPaymentChecklistItem) {
        self.init(
            checklistId: item.id,
            activityId: item.boardGameActivityId,
            title: item.title.isEmpty ? String(item.boardGameActivityId.prefix(8)) : item.title,
            venueName: item.venueName ?? item.address,
            startsAt: item.startsAt,
            isAllSettled: item.isAllSettled
        )
    }
}

extension MyChecklistItemRowUi {
    init(_ item: BoardGameMyPaymentChecklistItem) {
        self.init(
            itemId: item.id,
            activityId: item.boardGameActivityId,
            title: item.title.isEmpty ? String(item.boardGameActivityId.prefix(8)) : item.title,
            venueName: item.venueName ?? item.address,
            startsAt: item.startsAt,
            paid: item.paid,
            priceAmount: item.priceAmount,
            currency: item.currency
        )
    }
}
