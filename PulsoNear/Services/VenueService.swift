import PulsoLinkCore

/**
 * Near 门店门面（Android `VenueService`）：查询走 [VenueQueryStore]（key 带当前身份），
 * 写操作成功后一次 [VenueEventBus.invalidate]。
 */
struct VenueService: Sendable {
    let repository: VenueRepository
    let query: VenueQueryStore
    let eventBus: VenueEventBus
    let session: AuthSessionStore

    private var profileId: String { session.state.value.currentProfileId }

    /** 当前身份所在的门店（运营 / 管理 / 前台）；普通球友为空。 */
    func myVenues() async throws -> [MyVenue] {
        try await repository.listMyVenues()
    }

    func streamVenue(_ venueId: String) -> AsyncStream<QueryResponse<VenueDetail>> {
        query.detail.stream(VenueKey(venueId: venueId, profileId: profileId))
    }

    /** 计一次打开，并把新的浏览次数盖到缓存的详情和地图针上。 */
    func incrementView(_ venueId: String) async throws {
        let response = try await repository.incrementVenueView(venueId)
        await query.overlayView(venueId: venueId, view: response.view)
    }

    func getVenueByBuilding(_ buildingId: String) async throws -> VenueDetail? {
        try await repository.getVenueByBuilding(buildingId)
    }

    /** 读一次门店（帖子里的链接卡片），不走详情缓存。 */
    func getVenue(_ venueId: String) async throws -> VenueDetail {
        try await repository.getVenue(venueId)
    }

    func streamOfferings(_ venueId: String) -> AsyncStream<QueryResponse<[VenueOffering]>> {
        query.offerings.stream(VenueKey(venueId: venueId, profileId: profileId))
    }

    func streamNearby(_ key: NearbyVenuesKey) -> AsyncStream<QueryResponse<NearbyVenuesPage>> {
        query.nearby.stream(key)
    }

    func getNearby(_ key: NearbyVenuesKey) async throws -> NearbyVenuesPage {
        try await query.nearby.get(key)
    }

    /** Stripe 付款成功后 webhook 才改状态；让订阅方重拉。 */
    func invalidate() {
        eventBus.invalidate()
    }
}
