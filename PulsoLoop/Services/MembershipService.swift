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

/** 某运动在某球馆当前能用来付订场的时长包。 */
struct UsableBundlesKey: Hashable, Sendable {
    var venueId: String
    var sport: VenueSport
    var profileId: String
}

struct MyBundleKey: Hashable, Sendable {
    var bundleId: String
    var profileId: String
}

/** 会员和时长包的读缓存（Android `VenueQueryStore` 里这几项）；和球馆一起由 [VenueEventBus] 失效。 */
final class MembershipQueryStore: LogoutClearable {
    let membershipOffers: MemoryQuery<VenueKey, MembershipOffersGrid>
    let myVenueMembership: MemoryQuery<VenueKey, MyVenueMembership>
    let myMembershipPurchase: MemoryQuery<MyMembershipPurchaseKey, MyMembershipPurchase>
    let myMembership: MemoryQuery<MyMembershipKey, MyMembershipDetail>
    let bundleOffers: MemoryQuery<VenueKey, [BundleOffer]>
    let usableBundles: MemoryQuery<UsableBundlesKey, [MyBundle]>
    let myBundle: MemoryQuery<MyBundleKey, MyBundleDetail>

    init(memberships: MembershipRepository, bundles: BundleRepository, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        membershipOffers = MemoryQuery(invalidates: invalidates) { key in try await memberships.getMembershipOffers(key.venueId) }
        myVenueMembership = MemoryQuery(invalidates: invalidates) { key in MyVenueMembership(membership: try await memberships.getMyVenueMembership(key.venueId)) }
        myMembershipPurchase = MemoryQuery(invalidates: invalidates) { key in try await memberships.getMyMembershipPurchase(key.purchaseId) }
        myMembership = MemoryQuery(invalidates: invalidates) { key in try await memberships.getMyMembership(key.membershipId) }
        bundleOffers = MemoryQuery(invalidates: invalidates) { key in try await bundles.listBundleOffers(key.venueId) }
        usableBundles = MemoryQuery(invalidates: invalidates) { key in try await bundles.listUsableBundles(key.venueId, sport: key.sport) }
        myBundle = MemoryQuery(invalidates: invalidates) { key in try await bundles.getMyBundle(key.bundleId) }
    }

    func onLogout() async throws {
        await membershipOffers.clear()
        await myVenueMembership.clear()
        await myMembershipPurchase.clear()
        await myMembership.clear()
        await bundleOffers.clear()
        await usableBundles.clear()
        await myBundle.clear()
    }
}

/** 球馆会员门面（玩家侧，Android `MembershipService`）：和球馆共用 [VenueEventBus] 的失效。 */
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

/** 球馆时长包门面（玩家侧，Android `BundleService`）：和球馆共用 [VenueEventBus] 的失效。 */
struct BundleService: Sendable {
    let repository: BundleRepository
    let query: MembershipQueryStore
    let eventBus: VenueEventBus
    let session: AuthSessionStore

    private var profileId: String { session.state.value.currentProfileId }

    func streamOffers(_ venueId: String) -> AsyncStream<QueryResponse<[BundleOffer]>> {
        query.bundleOffers.stream(VenueKey(venueId: venueId, profileId: profileId))
    }

    func streamUsable(_ venueId: String, sport: VenueSport) -> AsyncStream<QueryResponse<[MyBundle]>> {
        query.usableBundles.stream(UsableBundlesKey(venueId: venueId, sport: sport, profileId: profileId))
    }

    /** 我的时长包；[statuses] 为 nil 时列出所有状态。 */
    @MainActor
    func pageMine(_ statuses: [BundleStatus]?) -> PagedList<MyBundle, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listMyBundles(MyBundlesRequest(offset: offset, limit: limit, statuses: statuses))
        }
    }

    func streamMyBundle(_ bundleId: String) -> AsyncStream<QueryResponse<MyBundleDetail>> {
        query.myBundle.stream(MyBundleKey(bundleId: bundleId, profileId: profileId))
    }

    /** 付款后等 webhook 落库：绕过缓存重拉。 */
    func refetchMyBundle(_ bundleId: String) async throws -> MyBundleDetail {
        try await query.myBundle.fresh(MyBundleKey(bundleId: bundleId, profileId: profileId))
    }

    func quote(_ venueId: String, offerId: String) async throws -> BundlePriceQuote {
        try await repository.quoteBundleOffer(venueId, offerId: offerId)
    }

    func purchase(_ venueId: String, offerId: String, paymentMethod: BundlePaymentMethod) async throws -> BundlePurchaseResult {
        let out = try await repository.purchaseBundleOffer(venueId, offerId: offerId, paymentMethod: paymentMethod)
        eventBus.invalidate()
        return out
    }

    func cancelMine(_ bundleId: String) async throws -> MyBundle {
        let out = try await repository.cancelMyBundle(bundleId)
        eventBus.invalidate()
        return out
    }

    func invalidate() {
        eventBus.invalidate()
    }
}
