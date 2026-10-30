import Foundation

/** 某个身份的私聊或群聊列表第一页（App 里不分页）。 */
public struct ConversationListKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let limit: Int

    public init(accountId: String, profileId: String, limit: Int = 100) {
        self.accountId = accountId
        self.profileId = profileId
        self.limit = limit
    }
}

public struct GroupConversationKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let conversationId: String

    public init(accountId: String, profileId: String, conversationId: String) {
        self.accountId = accountId
        self.profileId = profileId
        self.conversationId = conversationId
    }
}

public struct ConversationMessagesKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let conversationType: ConversationType
    public let conversationId: String
    public let limit: Int
    public let cursor: String?

    public init(accountId: String, profileId: String, conversationType: ConversationType, conversationId: String, limit: Int = 50, cursor: String? = nil) {
        self.accountId = accountId
        self.profileId = profileId
        self.conversationType = conversationType
        self.conversationId = conversationId
        self.limit = limit
        self.cursor = cursor
    }
}

/** 未读红点（私聊 / 群聊 / 通知）按身份缓存。 */
public struct ChatUnreadKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String

    public init(accountId: String, profileId: String) {
        self.accountId = accountId
        self.profileId = profileId
    }
}

/**
 * 通信查询（Android `CommunicationQueryStore`）：会话列表以本地库为准（离线优先）；
 * 群详情、消息页、未读红点只在内存里。
 */
public final class CommunicationQueryStore: LogoutClearable {
    private let direct: PersistedQuery<ConversationListKey, ListWithTotal<ConversationDirectItem>, [ConversationDirectItem]>
    private let groups: PersistedQuery<ConversationListKey, ListWithTotal<ConversationGroupItem>, [ConversationGroupItem]>
    private let groupDetail: MemoryQuery<GroupConversationKey, ConversationGroupDetail>
    private let messages: MemoryQuery<ConversationMessagesKey, ListWithNextCursor<ChatMessageItem>>
    private let directUnread: MemoryQuery<ChatUnreadKey, HasUnreadResponse>
    private let groupUnread: MemoryQuery<ChatUnreadKey, HasUnreadResponse>
    private let notificationUnread: MemoryQuery<ChatUnreadKey, HasUnreadResponse>

    public init(communication: CommunicationRepository, local: CommunicationLocalStore, bus: CommunicationEventBus) {
        let conversations: @Sendable () -> AsyncStream<Void> = { bus.signals { $0 == .invalidateConversations } }
        direct = PersistedQuery(
            invalidates: conversations,
            fetcher: { key in try await communication.listDirectConversations(limit: key.limit, offset: 0) },
            reader: { key in local.observeDirect(key.profileId) },
            writer: { key, page in try await local.replaceDirect(key.profileId, page) },
            delete: { key in try await local.clearConversations(key.profileId, isGroup: false) },
            deleteAll: { try await local.clearAllConversations() }
        )
        groups = PersistedQuery(
            invalidates: conversations,
            fetcher: { key in try await communication.listGroupConversations(limit: key.limit, offset: 0) },
            reader: { key in local.observeGroups(key.profileId) },
            writer: { key, page in try await local.replaceGroups(key.profileId, page) },
            delete: { key in try await local.clearConversations(key.profileId, isGroup: true) },
            deleteAll: { try await local.clearAllConversations() }
        )
        groupDetail = MemoryQuery(invalidates: { bus.signals { $0 == .invalidateConversations || $0 == .invalidateGroupMembers } }) { key in
            try await communication.getGroupConversation(key.conversationId)
        }
        messages = MemoryQuery(invalidates: conversations) { key in
            try await communication.listConversationMessages(key.conversationType, key.conversationId, limit: key.limit, cursor: key.cursor)
        }
        directUnread = MemoryQuery(invalidates: conversations) { _ in try await communication.checkDirectChatUnread() }
        groupUnread = MemoryQuery(invalidates: conversations) { _ in try await communication.checkGroupChatUnread() }
        // Android `NotificationUnreadQueryStore`。
        notificationUnread = MemoryQuery(invalidates: { bus.signals { $0 == .invalidateNotifications } }) { _ in
            try await communication.checkUnreadNotifications()
        }
    }

    public func streamDirectConversations(_ key: ConversationListKey) -> AsyncStream<QueryResponse<[ConversationDirectItem]>> { direct.stream(key) }
    public func streamGroupConversations(_ key: ConversationListKey) -> AsyncStream<QueryResponse<[ConversationGroupItem]>> { groups.stream(key) }

    public func freshConversations(_ key: ConversationListKey) async throws {
        _ = try await direct.fresh(key)
        _ = try await groups.fresh(key)
    }

    public func streamGroupDetail(_ key: GroupConversationKey, refresh: Bool = true) -> AsyncStream<QueryResponse<ConversationGroupDetail>> {
        groupDetail.stream(key, refresh: refresh)
    }

    public func getGroupDetail(_ key: GroupConversationKey) async throws -> ConversationGroupDetail { try await groupDetail.get(key) }

    public func streamMessages(_ key: ConversationMessagesKey, refresh: Bool = true) -> AsyncStream<QueryResponse<ListWithNextCursor<ChatMessageItem>>> {
        messages.stream(key, refresh: refresh)
    }

    public func getMessages(_ key: ConversationMessagesKey) async throws -> ListWithNextCursor<ChatMessageItem> { try await messages.get(key) }
    public func freshMessages(_ key: ConversationMessagesKey) async throws -> ListWithNextCursor<ChatMessageItem> { try await messages.fresh(key) }

    public func getDirectUnread(_ key: ChatUnreadKey) async throws -> HasUnreadResponse { try await directUnread.get(key) }
    public func freshDirectUnread(_ key: ChatUnreadKey) async throws -> HasUnreadResponse { try await directUnread.fresh(key) }
    public func getGroupUnread(_ key: ChatUnreadKey) async throws -> HasUnreadResponse { try await groupUnread.get(key) }
    public func freshGroupUnread(_ key: ChatUnreadKey) async throws -> HasUnreadResponse { try await groupUnread.fresh(key) }

    public func streamNotificationUnread(_ key: ChatUnreadKey) -> AsyncStream<QueryResponse<HasUnreadResponse>> { notificationUnread.stream(key) }
    public func getNotificationUnread(_ key: ChatUnreadKey) async throws -> HasUnreadResponse { try await notificationUnread.get(key) }
    public func freshNotificationUnread(_ key: ChatUnreadKey) async throws -> HasUnreadResponse { try await notificationUnread.fresh(key) }

    /** 登出：清内存里的页；会话列表在本地库里，由 [PulsoDatabase.clearAll] 清。 */
    public func onLogout() async throws {
        await groupDetail.clear()
        await messages.clear()
        await directUnread.clear()
        await groupUnread.clear()
        await notificationUnread.clear()
    }
}
