import PulsoLinkCore

/** 球馆会员仓储（玩家侧，Android `MembershipRepository`）。 */
struct MembershipRepository: Sendable {
    let api: MembershipAPI

    func getMembershipOffers(_ venueId: String) async throws -> MembershipOffersGrid {
        try await api.getMembershipOffers(venueId: venueId).dataOrThrow("GetMembershipOffers")
    }

    /** 没开过卡返回 nil。 */
    func getMyVenueMembership(_ venueId: String) async throws -> MyMembership? {
        try await api.getMyVenueMembership(venueId: venueId).data
    }

    func quoteMembershipOffer(_ venueId: String, offerId: String) async throws -> MembershipPriceQuote {
        try await api.quoteMembershipOffer(venueId: venueId, offerId: offerId).dataOrThrow("QuoteMembershipOffer")
    }

    func purchaseMembershipOffer(_ venueId: String, offerId: String, paymentMethod: MembershipPaymentMethod) async throws -> MembershipPurchaseResult {
        try await api.purchaseMembershipOffer(venueId: venueId, offerId: offerId, MembershipPurchaseRequest(paymentMethod: paymentMethod))
            .dataOrThrow("PurchaseMembershipOffer")
    }

    func listMyMemberships(_ body: MyMembershipsRequest) async throws -> ListWithTotal<MyMembership> {
        try await api.listMyMemberships(body).dataOrThrow("ListMyMemberships")
    }

    func listMyMembershipPurchases(_ body: MyMembershipPurchasesRequest) async throws -> ListWithTotal<MyMembershipPurchase> {
        try await api.listMyMembershipPurchases(body).dataOrThrow("ListMyMembershipPurchases")
    }

    func getMyMembershipPurchase(_ purchaseId: String) async throws -> MyMembershipPurchase {
        try await api.getMyMembershipPurchase(purchaseId: purchaseId).dataOrThrow("GetMyMembershipPurchase")
    }

    func cancelMyMembershipPurchase(_ purchaseId: String) async throws -> MyMembershipPurchase {
        try await api.cancelMyMembershipPurchase(purchaseId: purchaseId).dataOrThrow("CancelMyMembershipPurchase")
    }

    func getMyMembership(_ membershipId: String) async throws -> MyMembershipDetail {
        try await api.getMyMembership(membershipId: membershipId).dataOrThrow("GetMyMembership")
    }
}

/** 球馆储值时长包仓储（玩家侧，Android `BundleRepository`）。 */
struct BundleRepository: Sendable {
    let api: BundleAPI

    func listBundleOffers(_ venueId: String) async throws -> [BundleOffer] {
        try await api.listBundleOffers(venueId: venueId).dataOrThrow("ListBundleOffers")
    }

    func quoteBundleOffer(_ venueId: String, offerId: String) async throws -> BundlePriceQuote {
        try await api.quoteBundleOffer(venueId: venueId, offerId: offerId).dataOrThrow("QuoteBundleOffer")
    }

    func purchaseBundleOffer(_ venueId: String, offerId: String, paymentMethod: BundlePaymentMethod) async throws -> BundlePurchaseResult {
        try await api.purchaseBundleOffer(venueId: venueId, offerId: offerId, BundlePurchaseRequest(paymentMethod: paymentMethod)).dataOrThrow("PurchaseBundleOffer")
    }

    func listUsableBundles(_ venueId: String, sport: VenueSport) async throws -> [MyBundle] {
        try await api.listUsableBundles(venueId: venueId, sport: sport.rawValue).dataOrThrow("ListUsableBundles")
    }

    func listMyBundles(_ body: MyBundlesRequest) async throws -> ListWithTotal<MyBundle> {
        try await api.listMyBundles(body).dataOrThrow("ListMyBundles")
    }

    func getMyBundle(_ bundleId: String) async throws -> MyBundleDetail {
        try await api.getMyBundle(bundleId: bundleId).dataOrThrow("GetMyBundle")
    }

    func cancelMyBundle(_ bundleId: String) async throws -> MyBundle {
        try await api.cancelMyBundle(bundleId: bundleId).dataOrThrow("CancelMyBundle")
    }
}
