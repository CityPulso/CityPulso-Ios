import Foundation

/** 一张关系列表的搜索和排序；关键字匹配昵称、用户名或城市（Android `SocialRelationFilter`）。 */
public struct SocialRelationFilter: Hashable, Sendable {
    public var keyword: String
    public var sort: SocialRelationSort

    public init(keyword: String = "", sort: SocialRelationSort = .fallback) {
        self.keyword = keyword
        self.sort = sort
    }

    public var isDefault: Bool { keyword.trimmingCharacters(in: .whitespaces).isEmpty && sort == .fallback }
}

/** Social 域门面（Android `SocialService`，WEB `hooks/social.ts`）：读 + 写，失效在这一层发齐。 */
public struct SocialService: Sendable {
    private static let relationPageSize = 30

    private let social: SocialRepository
    private let query: SocialQueryStore
    private let bus: SocialEventBus
    private let local: SocialLocalStore
    private let sessionStore: AuthSessionStore

    public init(social: SocialRepository, query: SocialQueryStore, bus: SocialEventBus, local: SocialLocalStore, sessionStore: AuthSessionStore) {
        self.social = social
        self.query = query
        self.bus = bus
        self.local = local
        self.sessionStore = sessionStore
    }

    /* ------------------------------ paged relation tabs ------------------------------ */

    @MainActor
    public func pageFriends(_ profileId: String, _ filter: SocialRelationFilter = SocialRelationFilter()) -> PagedList<FriendItem, Int> {
        pager(profileId, filter, .friends, .invalidateFriends) { try await social.listFriends($0) }
    }

    @MainActor
    public func pageFollowing(_ profileId: String, _ filter: SocialRelationFilter = SocialRelationFilter()) -> PagedList<FollowingItem, Int> {
        pager(profileId, filter, .following, .invalidateFollowing) { try await social.listFollowing($0) }
    }

    @MainActor
    public func pageFollowers(_ profileId: String, _ filter: SocialRelationFilter = SocialRelationFilter()) -> PagedList<FollowerItem, Int> {
        pager(profileId, filter, .followers, .invalidateFollowers) { try await social.listFollowers($0) }
    }

    @MainActor
    public func pageBlocked(_ profileId: String, _ filter: SocialRelationFilter = SocialRelationFilter()) -> PagedList<BlockedItem, Int> {
        pager(profileId, filter, .blocked, .invalidateBlocked) { try await social.listBlocked($0) }
    }

    /** 默认视图（无关键字、最新在前）每页都写回本地库；搜索或换排序只走网络。对应的失效会让列表重拉。 */
    @MainActor
    private func pager<T: Codable & Sendable>(
        _ profileId: String,
        _ filter: SocialRelationFilter,
        _ spec: SocialConnectionSpec<T>,
        _ invalidation: SocialEvent,
        _ fetch: @escaping @Sendable (SocialPaginationRequest) async throws -> ListWithTotal<T>
    ) -> PagedList<T, Int> {
        let bus = bus
        let local = local
        let keyword = filter.keyword.trimmingCharacters(in: .whitespaces)
        let sort = filter.sort
        let persist = filter.isDefault
        return .offset(pageSize: Self.relationPageSize, invalidates: { bus.signals { $0 == invalidation } }) { offset, limit in
            guard persist else {
                return try await fetch(SocialPaginationRequest(limit: limit, offset: offset, keyword: keyword, sort: sort))
            }
            let page = try await fetch(SocialPaginationRequest(limit: limit, offset: offset))
            if offset == 0 {
                try await local.replaceConnections(profileId, spec, page)
            } else {
                try await local.appendConnections(profileId, spec, page.items, start: offset, total: page.total)
            }
            return page
        }
    }

    /* ------------------------------ relation counts ------------------------------ */

    /** 一个关系数字，各自请求、各自填上；首次回来前是 nil。每次数字失效都重拉，失败时保留上一个数。 */
    public func relationCount(_ tab: SocialConnectionsTab) -> AsyncStream<Int?> {
        let social = social
        let pulses = bus.signals { $0 == .invalidateStats }
        return AsyncStream { continuation in
            let task = Task {
                var iterator = pulses.makeAsyncIterator()
                continuation.yield(nil)
                repeat {
                    let count: Int? = switch tab {
                    case .following: try? await social.getFollowingCount()
                    case .followers: try? await social.getFollowerCount()
                    case .friends: try? await social.getFriendCount()
                    }
                    if let count { continuation.yield(count) }
                } while await iterator.next() != nil
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /** 别人主页的关注 / 粉丝数（对方没公开的那项为 nil）；关注 / 取关后由页面自己重拉。 */
    public func getProfileRelationStats(_ profileId: String, _ profileScope: ProfileKind = .community) async throws -> ProfileRelationStats {
        try await social.getProfileRelationStats(profileId, profileScope)
    }

    /* ------------------------------ lists ------------------------------ */

    /** 好友第一页（选择器用），离线优先。 */
    public func streamFriends(_ key: FriendsKey) -> AsyncStream<QueryResponse<[FriendItem]>> { query.streamFriends(key) }
    public func getFriends(_ key: FriendsKey) async throws -> [FriendItem] { try await query.getFriends(key) }

    public func streamFriendRequests(_ key: FriendRequestsKey) -> AsyncStream<QueryResponse<[FriendRequestItem]>> { query.streamFriendRequests(key) }

    /** 重试 / 下拉刷新：活跃的请求列表重拉，本地行留着。 */
    public func refreshFriendRequests() { bus.emit(.invalidateFriendRequests(nil)) }

    /** 关系列表和好友选择器的重试。 */
    public func refreshRelations() {
        bus.emit(.invalidateFriends)
        bus.emit(.invalidateFollowing)
        bus.emit(.invalidateFollowers)
        bus.emit(.invalidateBlocked)
    }

    public func getPrivacy(_ key: SocialPrivacyKey) async throws -> PrivacySettings { try await query.getPrivacy(key) }
    public func getRelations(_ key: RelationStatusKey) async throws -> BatchRelationStatusResponse { try await query.getRelations(key) }

    /* ------------------------------ mutations ------------------------------ */

    /** [refreshFollowing] 为 false 时关注列表先不动，刚切换的那行留在原处，直到调 [refreshFollowing]。 */
    public func follow(_ targetProfileId: String, _ targetProfileScope: ProfileKind = .community, refreshFollowing: Bool = true) async throws {
        try await social.followProfile(SocialTargetProfile(targetProfileId: targetProfileId, targetProfileScope: targetProfileScope))
        bus.invalidateFollowRelation(refreshFollowing: refreshFollowing)
    }

    public func unfollow(_ targetProfileId: String, _ targetProfileScope: ProfileKind = .community, refreshFollowing: Bool = true) async throws {
        try await social.unfollowProfile(targetProfileId, targetProfileScope)
        bus.invalidateFollowRelation(refreshFollowing: refreshFollowing)
    }

    /** 用 `refreshFollowing: false` 切换过之后重拉关注列表。 */
    public func refreshFollowing() { bus.emit(.invalidateFollowing) }

    public func removeFriend(_ targetProfileId: String, _ targetProfileScope: ProfileKind = .community) async throws {
        try await social.removeFriend(targetProfileId, targetProfileScope)
        try await local.removeConnection(owner, .friend, targetProfileId)
        bus.emit(.invalidateFriends)
        bus.emit(.invalidateStats)
        bus.emit(.invalidateRelationStatus)
    }

    public func block(_ targetProfileId: String, _ targetProfileScope: ProfileKind = .community) async throws {
        try await social.blockProfile(BlockRequest(targetProfileId: targetProfileId, targetProfileScope: targetProfileScope))
        bus.invalidateBlockRelation()
    }

    public func removeFollower(_ targetProfileId: String, _ targetProfileScope: ProfileKind = .community) async throws {
        try await social.removeFollower(targetProfileId, targetProfileScope)
        try await local.removeConnection(owner, .follower, targetProfileId)
        bus.invalidateFollowRelation()
    }

    public func sendFriendRequest(_ body: SendFriendRequestRequest) async throws -> SendFriendRequestResponse {
        let response = try await social.sendFriendRequest(body)
        bus.emit(.invalidateFriendRequests(.outgoing))
        bus.emit(.invalidateRelationStatus)
        return response
    }

    public func acceptFriendRequest(_ friendRequestId: String) async throws {
        try await social.acceptFriendRequest(friendRequestId)
        try await local.removeRequest(owner, friendRequestId)
        bus.invalidateFriendRequestAccepted()
    }

    public func rejectFriendRequest(_ friendRequestId: String) async throws {
        try await social.rejectFriendRequest(friendRequestId)
        try await local.removeRequest(owner, friendRequestId)
        bus.emit(.invalidateFriendRequests(.incoming))
        bus.emit(.invalidateRelationStatus)
    }

    public func cancelFriendRequest(_ friendRequestId: String) async throws {
        try await social.cancelFriendRequest(friendRequestId)
        try await local.removeRequest(owner, friendRequestId)
        bus.emit(.invalidateFriendRequests(.outgoing))
        bus.emit(.invalidateRelationStatus)
    }

    public func unblock(_ targetProfileId: String, _ targetProfileScope: ProfileKind) async throws {
        try await social.unblockProfile(targetProfileId, targetProfileScope)
        try await local.removeConnection(owner, .blocked, targetProfileId)
        bus.emit(.invalidateBlocked)
        bus.emit(.invalidateStats)
        bus.emit(.invalidateRelationStatus)
    }

    public func updatePrivacy(_ body: UpdatePrivacySettingsRequest) async throws -> PrivacySettings {
        let saved = try await social.updateSocialPrivacySettings(body)
        bus.emit(.invalidatePrivacySettings)
        return saved
    }

    private var owner: String { sessionStore.state.value.currentProfileId }
}
