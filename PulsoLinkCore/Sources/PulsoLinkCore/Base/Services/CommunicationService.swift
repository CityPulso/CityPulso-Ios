import Foundation

/** Communication 域门面（Android `CommunicationService`，WEB `hooks/communication.ts`）：读 + 写，失效在这一层发齐。 */
public struct CommunicationService: Sendable {
    private static let notificationPageSize = 30

    private let communication: CommunicationRepository
    private let query: CommunicationQueryStore
    private let bus: CommunicationEventBus
    private let inbox: InboxIndicatorStore
    private let local: CommunicationLocalStore

    public init(communication: CommunicationRepository, query: CommunicationQueryStore, bus: CommunicationEventBus, inbox: InboxIndicatorStore, local: CommunicationLocalStore) {
        self.communication = communication
        self.query = query
        self.bus = bus
        self.inbox = inbox
        self.local = local
    }

    /**
     * [profileId] 的收件箱，离线优先：每次通知失效（推送、标已读、重连）都重拉第一页，本地旧行留着显示。
     * 「未读」筛选在本地行上做，拉取总是全部。
     */
    @MainActor
    public func notifications(_ profileId: String, unreadOnly: Bool) -> MediatedList<NotificationInboxItem> {
        let communication = communication
        let local = local
        let bus = bus
        return MediatedList(
            pageSize: Self.notificationPageSize,
            invalidates: { bus.signals { $0 == .invalidateNotifications } },
            reader: { local.observeNotifications(profileId, unreadOnly: unreadOnly) }
        ) { offset, limit in
            let page = try await communication.listNotifications(NotificationListRequest(limit: limit, offset: offset, unreadOnly: false))
            return try await local.writeNotifications(profileId, page, start: offset)
        }
    }

    public func observeUnreadNotificationCount(_ profileId: String) -> AsyncStream<Int> { local.observeUnreadCount(profileId) }

    public func streamDirectConversations(_ key: ConversationListKey) -> AsyncStream<QueryResponse<[ConversationDirectItem]>> { query.streamDirectConversations(key) }
    public func streamGroupConversations(_ key: ConversationListKey) -> AsyncStream<QueryResponse<[ConversationGroupItem]>> { query.streamGroupConversations(key) }

    /** 下拉刷新 / 重试：活跃的会话列表重拉，本地行留着。 */
    public func refreshConversations() { bus.emit(.invalidateConversations) }

    /** 收件箱重试。 */
    public func refreshNotifications() { bus.emit(.invalidateNotifications) }

    /** 消息页的通知铃铛红点（Android `NotificationUnreadQueryStore`）。 */
    public func streamNotificationUnread(_ key: ChatUnreadKey) -> AsyncStream<QueryResponse<HasUnreadResponse>> { query.streamNotificationUnread(key) }

    public func getGroupDetail(_ key: GroupConversationKey) async throws -> ConversationGroupDetail { try await query.getGroupDetail(key) }
    public func streamGroupDetail(_ key: GroupConversationKey) -> AsyncStream<QueryResponse<ConversationGroupDetail>> { query.streamGroupDetail(key) }
    public func getMessages(_ key: ConversationMessagesKey) async throws -> ListWithNextCursor<ChatMessageItem> { try await query.getMessages(key) }
    public func freshMessages(_ key: ConversationMessagesKey) async throws -> ListWithNextCursor<ChatMessageItem> { try await query.freshMessages(key) }

    public func createDirectConversation(_ body: CreateDirectRequest) async throws -> ConversationDirectDetail {
        let detail = try await communication.createDirectConversation(body)
        bus.emit(.invalidateConversations)
        return detail
    }

    public func createGroupConversation(_ body: CreateGroupRequest) async throws -> CreateGroupResult {
        let result = try await communication.createGroupConversation(body)
        bus.emit(.invalidateConversations)
        return result
    }

    public func sendChatMessage(_ body: SendMessageRequest) async throws {
        try await communication.sendChatMessage(body)
        bus.emit(.invalidateConversations)
    }

    /** 撤回自己的一条消息（会话里所有人都看不到）。 */
    public func deleteChatMessage(_ request: DeleteMessageRequest) async throws {
        try await communication.deleteChatMessage(request)
        bus.emit(.invalidateConversations)
    }

    public func getConversationSetting(_ type: ConversationType, _ conversationId: String) async throws -> ConversationProfileState {
        try await communication.getConversationSetting(type, conversationId)
    }

    public func updateConversationMute(_ type: ConversationType, _ conversationId: String, muted: Bool) async throws {
        try await communication.updateConversationMute(type, conversationId, UpdateMuteRequest(muted: muted))
        bus.emit(.invalidateConversationSetting)
        bus.emit(.invalidateConversations)
    }

    public func updateConversationPin(_ type: ConversationType, _ conversationId: String, pinned: Bool) async throws {
        try await communication.updateConversationPin(type, conversationId, UpdatePinRequest(pinned: pinned))
        bus.emit(.invalidateConversationSetting)
        bus.emit(.invalidateConversations)
    }

    public func updateConversationCustomTitle(_ type: ConversationType, _ conversationId: String, title: String?) async throws {
        try await communication.updateConversationCustomTitle(type, conversationId, UpdateCustomTitleRequest(title: title))
        bus.emit(.invalidateConversationSetting)
        bus.emit(.invalidateConversations)
    }

    public func listGroupMembers(_ conversationId: String, limit: Int? = nil, offset: Int? = nil) async throws -> ListWithTotal<ConversationMember> {
        try await communication.listGroupMembers(conversationId, limit: limit, offset: offset)
    }

    public func addGroupMembers(_ conversationId: String, _ body: AddMembersRequest) async throws -> AddMembersResult {
        let result = try await communication.addGroupMembers(conversationId, body)
        bus.emit(.invalidateGroupMembers)
        bus.emit(.invalidateConversations)
        return result
    }

    public func removeGroupMember(_ conversationId: String, profileId: String, profileScope: ProfileKind) async throws {
        try await communication.removeGroupMember(conversationId, profileId: profileId, profileScope: profileScope)
        bus.emit(.invalidateGroupMembers)
        bus.emit(.invalidateConversations)
    }

    public func updateGroupConversation(_ conversationId: String, _ body: UpdateGroupRequest) async throws -> ConversationGroupDetail {
        let detail = try await communication.updateGroupConversation(conversationId, body)
        bus.emit(.invalidateConversations)
        return detail
    }

    public func leaveGroupConversation(_ conversationId: String) async throws {
        try await communication.leaveGroupConversation(conversationId)
        bus.emit(.invalidateConversations)
        bus.emit(.invalidateGroupMembers)
    }

    public func markConversationRead(_ type: ConversationType, _ conversationId: String, _ body: MarkReadRequest) async throws {
        try await communication.markConversationRead(type, conversationId, body)
        bus.emit(.invalidateConversations)
        try? await inbox.recheckDirectChatUnread()
        try? await inbox.recheckGroupChatUnread()
    }

    public func markNotificationRead(_ profileId: String, _ notificationId: String) async throws {
        try await communication.markNotificationRead(notificationId)
        try await local.markNotificationRead(profileId, notificationId)
        bus.emit(.invalidateNotifications)
        try? await inbox.recheckNotificationUnread()
    }

    public func markAllNotificationsRead(_ profileId: String) async throws {
        try await communication.markAllNotificationsRead()
        try await local.markAllNotificationsRead(profileId)
        bus.emit(.invalidateNotifications)
        try? await inbox.recheckNotificationUnread()
    }
}
