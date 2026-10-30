import Foundation

/** 通信仓储（Android `CommunicationRepository`）——方法与 WEB `ApiCommunicationRepository` 逐一对齐；实时 token 走 [RealtimeAPI]。 */
public struct CommunicationRepository: Sendable {
    private let api: CommunicationAPI
    private let realtimeAPI: RealtimeAPI

    public init(api: CommunicationAPI, realtimeAPI: RealtimeAPI) {
        self.api = api
        self.realtimeAPI = realtimeAPI
    }

    /* ------------------------------ realtime ------------------------------ */

    public func getRealtimeToken() async throws -> RealtimeTokenResponse {
        try await realtimeAPI.getRealtimeToken().dataOrThrow("GetRealtimeToken")
    }

    /* ------------------------------ 通知收件箱 ------------------------------ */

    public func listNotifications(_ body: NotificationListRequest = NotificationListRequest()) async throws -> ListWithTotal<NotificationInboxItem> {
        try await api.listNotifications(body).dataOrThrow("ListNotifications")
    }

    public func checkUnreadNotifications() async throws -> HasUnreadResponse {
        try await api.checkUnreadNotifications().dataOrThrow("CheckUnreadNotifications")
    }

    public func countUnreadNotifications() async throws -> NotificationUnreadCount {
        try await api.countUnreadNotifications().dataOrThrow("CountUnreadNotifications")
    }

    public func markNotificationRead(_ notificationId: String) async throws { try await api.markNotificationRead(notificationId: notificationId) }
    public func markAllNotificationsRead() async throws { try await api.markAllNotificationsRead() }

    /* ------------------------------ 会话 ------------------------------ */

    public func createDirectConversation(_ body: CreateDirectRequest) async throws -> ConversationDirectDetail {
        try await api.createDirectConversation(body).dataOrThrow("CreateDirectConversation")
    }

    public func checkDirectChatUnread() async throws -> HasUnreadResponse { try await api.checkDirectChatUnread().dataOrThrow("CheckDirectChatUnread") }
    public func checkGroupChatUnread() async throws -> HasUnreadResponse { try await api.checkGroupChatUnread().dataOrThrow("CheckGroupChatUnread") }

    public func listDirectConversations(limit: Int? = nil, offset: Int? = nil) async throws -> ListWithTotal<ConversationDirectItem> {
        try await api.listDirectConversations(limit: limit, offset: offset).dataOrThrow("ListDirectConversations")
    }

    public func createGroupConversation(_ body: CreateGroupRequest) async throws -> CreateGroupResult {
        try await api.createGroupConversation(body).dataOrThrow("CreateGroupConversation")
    }

    public func listGroupConversations(limit: Int? = nil, offset: Int? = nil) async throws -> ListWithTotal<ConversationGroupItem> {
        try await api.listGroupConversations(limit: limit, offset: offset).dataOrThrow("ListGroupConversations")
    }

    public func getGroupConversation(_ conversationId: String) async throws -> ConversationGroupDetail {
        try await api.getGroupConversation(conversationId: conversationId).dataOrThrow("GetGroupConversation")
    }

    public func updateGroupConversation(_ conversationId: String, _ body: UpdateGroupRequest) async throws -> ConversationGroupDetail {
        try await api.updateGroupConversation(conversationId: conversationId, body).dataOrThrow("UpdateGroupConversation")
    }

    public func leaveGroupConversation(_ conversationId: String) async throws { try await api.leaveGroupConversation(conversationId: conversationId) }

    public func listGroupMembers(_ conversationId: String, limit: Int? = nil, offset: Int? = nil) async throws -> ListWithTotal<ConversationMember> {
        try await api.listGroupMembers(conversationId: conversationId, limit: limit, offset: offset).dataOrThrow("ListGroupMembers")
    }

    public func addGroupMembers(_ conversationId: String, _ body: AddMembersRequest) async throws -> AddMembersResult {
        try await api.addGroupMembers(conversationId: conversationId, body).dataOrThrow("AddGroupMembers")
    }

    public func removeGroupMember(_ conversationId: String, profileId: String, profileScope: ProfileKind) async throws {
        try await api.removeGroupMember(conversationId: conversationId, profileId: profileId, profileScope: profileScope.rawValue)
    }

    public func listConversationMessages(_ type: ConversationType, _ conversationId: String, limit: Int? = nil, cursor: String? = nil) async throws -> ListWithNextCursor<ChatMessageItem> {
        try await api.listConversationMessages(conversationType: type.rawValue, conversationId: conversationId, limit: limit, cursor: cursor)
            .dataOrThrow("ListConversationMessages")
    }

    public func getConversationSetting(_ type: ConversationType, _ conversationId: String) async throws -> ConversationProfileState {
        try await api.getConversationSetting(conversationType: type.rawValue, conversationId: conversationId).dataOrThrow("GetConversationSetting")
    }

    public func markConversationRead(_ type: ConversationType, _ conversationId: String, _ body: MarkReadRequest) async throws {
        try await api.markConversationRead(conversationType: type.rawValue, conversationId: conversationId, body)
    }

    public func updateConversationMute(_ type: ConversationType, _ conversationId: String, _ body: UpdateMuteRequest) async throws {
        try await api.updateConversationMute(conversationType: type.rawValue, conversationId: conversationId, body)
    }

    public func updateConversationPin(_ type: ConversationType, _ conversationId: String, _ body: UpdatePinRequest) async throws {
        try await api.updateConversationPin(conversationType: type.rawValue, conversationId: conversationId, body)
    }

    public func updateConversationCustomTitle(_ type: ConversationType, _ conversationId: String, _ body: UpdateCustomTitleRequest) async throws {
        try await api.updateConversationCustomTitle(conversationType: type.rawValue, conversationId: conversationId, body)
    }

    /* ------------------------------ 消息 ------------------------------ */

    public func sendChatMessage(_ body: SendMessageRequest) async throws { try await api.sendChatMessage(body) }

    public func editChatMessage(_ request: EditMessageRequest) async throws {
        try await api.editChatMessage(
            messageId: request.messageId,
            EditMessageBody(conversationType: request.conversationType.rawValue, conversationId: request.conversationId, content: request.content)
        )
    }

    public func deleteChatMessage(_ request: DeleteMessageRequest) async throws {
        try await api.deleteChatMessage(messageId: request.messageId, conversationType: request.conversationType.rawValue, conversationId: request.conversationId)
    }
}
