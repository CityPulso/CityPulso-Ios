import Foundation

/** 小红点（不带数字）——对应 Android `InboxIndicators`、WEB `stores/inboxIndicator.ts`。 */
public struct InboxIndicators: Equatable, Sendable {
    public var hasDirectChatUnread = false
    public var hasGroupChatUnread = false
    public var hasNotificationUnread = false
    public var hasFriendRequestIncoming = false

    public init() {}

    /** 消息页的红点：私聊或群聊有未读。 */
    public var hasChatUnread: Bool { hasDirectChatUnread || hasGroupChatUnread }
}

/** 小红点状态（Android `InboxIndicatorStore`）：登录 / 回到前台时 [sync]，写操作和实时推送后单项 recheck。 */
public final class InboxIndicatorStore: LogoutClearable {
    public let state = StateBroadcast(InboxIndicators())

    private let sessionStore: AuthSessionStore
    private let communicationQuery: CommunicationQueryStore
    private let socialQuery: SocialQueryStore

    public init(sessionStore: AuthSessionStore, communicationQuery: CommunicationQueryStore, socialQuery: SocialQueryStore) {
        self.sessionStore = sessionStore
        self.communicationQuery = communicationQuery
        self.socialQuery = socialQuery
    }

    public func setDirectChatUnread(_ value: Bool) { state.update { $0.hasDirectChatUnread = value } }
    public func setGroupChatUnread(_ value: Bool) { state.update { $0.hasGroupChatUnread = value } }
    public func setNotificationUnread(_ value: Bool) { state.update { $0.hasNotificationUnread = value } }
    public func setFriendRequestIncoming(_ value: Bool) { state.update { $0.hasFriendRequestIncoming = value } }

    public func onLogout() async throws {
        state.set(InboxIndicators())
    }

    /** 四项并发全量同步。 */
    public func sync() async throws {
        let key = chatKey
        async let direct = communicationQuery.getDirectUnread(key)
        async let group = communicationQuery.getGroupUnread(key)
        async let notifications = communicationQuery.getNotificationUnread(key)
        async let requests = socialQuery.getIncomingFriendRequests(FriendRequestIncomingKey(accountId: key.accountId, profileId: key.profileId))
        var next = InboxIndicators()
        next.hasDirectChatUnread = try await direct.hasUnread
        next.hasGroupChatUnread = try await group.hasUnread
        next.hasNotificationUnread = try await notifications.hasUnread
        next.hasFriendRequestIncoming = try await requests.hasPending
        state.set(next)
    }

    public func recheckDirectChatUnread() async throws { setDirectChatUnread(try await communicationQuery.freshDirectUnread(chatKey).hasUnread) }
    public func recheckGroupChatUnread() async throws { setGroupChatUnread(try await communicationQuery.freshGroupUnread(chatKey).hasUnread) }
    public func recheckNotificationUnread() async throws { setNotificationUnread(try await communicationQuery.freshNotificationUnread(chatKey).hasUnread) }

    public func recheckFriendRequestIncoming() async throws {
        let key = chatKey
        setFriendRequestIncoming(try await socialQuery.freshIncomingFriendRequests(FriendRequestIncomingKey(accountId: key.accountId, profileId: key.profileId)).hasPending)
    }

    private var chatKey: ChatUnreadKey {
        let session = sessionStore.state.value
        return ChatUnreadKey(accountId: session.currentAccountId, profileId: session.currentProfileId)
    }
}
