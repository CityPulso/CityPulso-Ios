import PulsoLinkCore

/** 「我的会员」可能为空（没开过卡）；缓存的值不能是 nil，所以包一层（Android `MyVenueMembership`）。 */
struct MyVenueMembership: Hashable, Sendable {
    let membership: MyMembership?
}

struct MyMembershipPurchaseKey: Hashable, Sendable {
    var purchaseId: String
    var profileId: String
}

struct MyMembershipKey: Hashable, Sendable {
    var membershipId: String
    var profileId: String
}

/** 会员的读缓存（Android `VenueQueryStore` 里这几项）；和门店一起由 [VenueEventBus] 失效。 */
final class MembershipQueryStore: LogoutClearable {
    let membershipOffers: MemoryQuery<VenueKey, MembershipOffersGrid>
    let myVenueMembership: MemoryQuery<VenueKey, MyVenueMembership>
    let myMembershipPurchase: MemoryQuery<MyMembershipPurchaseKey, MyMembershipPurchase>
    let myMembership: MemoryQuery<MyMembershipKey, MyMembershipDetail>

    init(memberships: MembershipRepository, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        membershipOffers = MemoryQuery(invalidates: invalidates) { key in try await memberships.getMembershipOffers(key.venueId) }
        myVenueMembership = MemoryQuery(invalidates: invalidates) { key in MyVenueMembership(membership: try await memberships.getMyVenueMembership(key.venueId)) }
        myMembershipPurchase = MemoryQuery(invalidates: invalidates) { key in try await memberships.getMyMembershipPurchase(key.purchaseId) }
        myMembership = MemoryQuery(invalidates: invalidates) { key in try await memberships.getMyMembership(key.membershipId) }
    }

    func onLogout() async throws {
        await membershipOffers.clear()
        await myVenueMembership.clear()
        await myMembershipPurchase.clear()
        await myMembership.clear()
    }
}

/** 门店会员门面（玩家侧，Android `MembershipService`）：和门店共用 [VenueEventBus] 的失效。 */
struct MembershipService: Sendable {
    let repository: MembershipRepository
    let query: MembershipQueryStore
    let eventBus: VenueEventBus
    let session: AuthSessionStore

    private var profileId: String { session.state.value.currentProfileId }

    func streamOffers(_ venueId: String) -> AsyncStream<QueryResponse<MembershipOffersGrid>> {
        query.membershipOffers.stream(VenueKey(venueId: venueId, profileId: profileId))
    }

    func streamMine(_ venueId: String) -> AsyncStream<QueryResponse<MyVenueMembership>> {
        query.myVenueMembership.stream(VenueKey(venueId: venueId, profileId: profileId))
    }

    /** 付款后等 webhook 落库：绕过缓存重拉。 */
    func refetchMine(_ venueId: String) async throws -> MyVenueMembership {
        try await query.myVenueMembership.fresh(VenueKey(venueId: venueId, profileId: profileId))
    }

    /** 服务端顺序：有效的卡在前，然后最新的。 */
    @MainActor
    func pageMyMemberships() -> PagedList<MyMembership, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listMyMemberships(MyMembershipsRequest(offset: offset, limit: limit))
        }
    }

    /** 只要等待确认的申请，最新的在前。 */
    @MainActor
    func pageMyWaitingPurchases() -> PagedList<MyMembershipPurchase, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listMyMembershipPurchases(MyMembershipPurchasesRequest(offset: offset, limit: limit, statuses: [.pending]))
        }
    }

    func streamMyPurchase(_ purchaseId: String) -> AsyncStream<QueryResponse<MyMembershipPurchase>> {
        query.myMembershipPurchase.stream(MyMembershipPurchaseKey(purchaseId: purchaseId, profileId: profileId))
    }

    func cancelMyPurchase(_ purchaseId: String) async throws -> MyMembershipPurchase {
        let out = try await repository.cancelMyMembershipPurchase(purchaseId)
        eventBus.invalidate()
        return out
    }

    func streamMyMembership(_ membershipId: String) -> AsyncStream<QueryResponse<MyMembershipDetail>> {
        query.myMembership.stream(MyMembershipKey(membershipId: membershipId, profileId: profileId))
    }

    func quote(_ venueId: String, offerId: String) async throws -> MembershipPriceQuote {
        try await repository.quoteMembershipOffer(venueId, offerId: offerId)
    }

    func purchase(_ venueId: String, offerId: String, paymentMethod: MembershipPaymentMethod) async throws -> MembershipPurchaseResult {
        let out = try await repository.purchaseMembershipOffer(venueId, offerId: offerId, paymentMethod: paymentMethod)
        eventBus.invalidate()
        return out
    }

    func invalidate() {
        eventBus.invalidate()
    }
}
