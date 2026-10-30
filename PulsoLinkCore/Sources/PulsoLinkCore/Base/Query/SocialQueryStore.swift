import Foundation

/** 某个身份好友列表的第一页（选择器用）；分页的关系列表走 [SocialService]。 */
public struct FriendsKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let limit: Int

    public init(accountId: String, profileId: String, limit: Int = 100) {
        self.accountId = accountId
        self.profileId = profileId
        self.limit = limit
    }
}

public struct FriendRequestsKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let limit: Int
    public let direction: SocialFriendRequestDirection?
    public let status: SocialFriendRequestStatus?

    public init(accountId: String, profileId: String, limit: Int = 100, direction: SocialFriendRequestDirection? = nil, status: SocialFriendRequestStatus? = nil) {
        self.accountId = accountId
        self.profileId = profileId
        self.limit = limit
        self.direction = direction
        self.status = status
    }

    /** 这组筛选在本地库里的分区。 */
    public var listKey: String { "\(direction?.rawValue ?? "any"):\(status?.rawValue ?? "any")" }
}

public struct SocialPrivacyKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String

    public init(accountId: String, profileId: String) {
        self.accountId = accountId
        self.profileId = profileId
    }
}

public struct RelationStatusKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let targets: [SocialTargetProfile]

    public init(accountId: String, profileId: String, targets: [SocialTargetProfile]) {
        self.accountId = accountId
        self.profileId = profileId
        self.targets = targets
    }
}

public struct FriendRequestIncomingKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String

    public init(accountId: String, profileId: String) {
        self.accountId = accountId
        self.profileId = profileId
    }
}

/**
 * 社交查询（Android `SocialQueryStore`）：好友第一页、好友请求以本地库为准（离线优先）；
 * 隐私、关系状态、有没有新请求这些小查询只在内存里。
 */
public final class SocialQueryStore: LogoutClearable {
    private let friends: PersistedQuery<FriendsKey, ListWithTotal<FriendItem>, [FriendItem]>
    private let friendRequests: PersistedQuery<FriendRequestsKey, ListWithTotal<FriendRequestItem>, [FriendRequestItem]>
    private let privacy: MemoryQuery<SocialPrivacyKey, PrivacySettings>
    private let relations: MemoryQuery<RelationStatusKey, BatchRelationStatusResponse>
    private let incomingCheck: MemoryQuery<FriendRequestIncomingKey, IncomingFriendRequestCheck>

    public init(social: SocialRepository, local: SocialLocalStore, bus: SocialEventBus) {
        friends = PersistedQuery(
            invalidates: { bus.signals { $0 == .invalidateFriends } },
            fetcher: { key in try await social.listFriends(SocialPaginationRequest(limit: key.limit, offset: 0)) },
            reader: { key in local.observeConnections(key.profileId, .friends) },
            writer: { key, page in try await local.replaceConnections(key.profileId, .friends, page) },
            delete: { key in try await local.clearConnections(key.profileId, .friends) },
            deleteAll: { try await local.clearKind(.friend) }
        )
        friendRequests = PersistedQuery(
            invalidates: { bus.signals(where: \.isFriendRequests) },
            fetcher: { key in
                try await social.listFriendRequests(FriendRequestListRequest(limit: key.limit, offset: 0, direction: key.direction, status: key.status))
            },
            reader: { key in local.observeRequests(key.profileId, key.listKey) },
            writer: { key, page in try await local.replaceRequests(key.profileId, key.listKey, page) },
            delete: { key in try await local.clearRequests(key.profileId, key.listKey) },
            deleteAll: { try await local.clearAllRequests() }
        )
        privacy = MemoryQuery(invalidates: { bus.signals { $0 == .invalidatePrivacySettings } }) { _ in
            try await social.getSocialPrivacySettings()
        }
        relations = MemoryQuery(invalidates: { bus.signals { $0 == .invalidateRelationStatus } }) { key in
            try await social.batchGetRelationStatus(BatchRelationStatusRequest(targetProfiles: key.targets))
        }
        incomingCheck = MemoryQuery(invalidates: { bus.signals(where: \.isFriendRequests) }) { _ in
            try await social.checkIncomingFriendRequests()
        }
    }

    public func streamFriends(_ key: FriendsKey) -> AsyncStream<QueryResponse<[FriendItem]>> { friends.stream(key) }
    public func getFriends(_ key: FriendsKey) async throws -> [FriendItem] { try await friends.get(key) }

    public func streamFriendRequests(_ key: FriendRequestsKey) -> AsyncStream<QueryResponse<[FriendRequestItem]>> { friendRequests.stream(key) }

    public func streamPrivacy(_ key: SocialPrivacyKey, refresh: Bool = true) -> AsyncStream<QueryResponse<PrivacySettings>> { privacy.stream(key, refresh: refresh) }
    public func getPrivacy(_ key: SocialPrivacyKey) async throws -> PrivacySettings { try await privacy.get(key) }

    public func streamRelations(_ key: RelationStatusKey, refresh: Bool = true) -> AsyncStream<QueryResponse<BatchRelationStatusResponse>> {
        relations.stream(key, refresh: refresh)
    }

    public func getRelations(_ key: RelationStatusKey) async throws -> BatchRelationStatusResponse { try await relations.get(key) }

    public func getIncomingFriendRequests(_ key: FriendRequestIncomingKey) async throws -> IncomingFriendRequestCheck { try await incomingCheck.get(key) }
    public func freshIncomingFriendRequests(_ key: FriendRequestIncomingKey) async throws -> IncomingFriendRequestCheck { try await incomingCheck.fresh(key) }

    /** 登出：清内存里的小查询；本地库由 [PulsoDatabase.clearAll] 清。 */
    public func onLogout() async throws {
        await privacy.clear()
        await relations.clear()
        await incomingCheck.clear()
    }
}
