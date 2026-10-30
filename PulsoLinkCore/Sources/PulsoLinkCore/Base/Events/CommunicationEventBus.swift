/** 通信域缓存失效事件（Android `CommunicationEvent`，WEB `events/communication.ts`）。 */
public enum CommunicationEvent: Sendable, Equatable {
    case invalidateNotifications
    case invalidateConversations
    case invalidateGroupMembers
    case invalidateConversationSetting
}

public typealias CommunicationEventBus = EventBroadcast<CommunicationEvent>
