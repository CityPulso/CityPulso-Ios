import PulsoLinkCore

/** 在别的页面选好、要发进某个会话的位置或卡片（Android `ChatShareDraft`）。 */
enum ChatShareDraft: Sendable {
    case location(conversationId: String, latitude: Double, longitude: Double, label: String?, address: String?)
    /** [type] 是一种分享卡片消息（活动 / 门店 / 建筑 / 帖子 / 论坛）。 */
    case card(conversationId: String, type: MessageType, card: ChatSharedCardContent)

    var conversationId: String {
        switch self {
        case let .location(id, _, _, _, _): id
        case let .card(id, _, _): id
        }
    }

    /** 变成要发的消息（Android `ChatShareDraft.toMessage`）。 */
    var message: (MessageType, ChatMessageContent) {
        switch self {
        case let .location(_, latitude, longitude, label, address):
            (.location, ChatMessageContent(location: ChatLocationContent(latitude: latitude, longitude: longitude, label: label, address: address)))
        case let .card(_, type, card):
            (type, ChatMessageContent(shared: card))
        }
    }
}

/** 选择页把草稿交给聊天室（Android `ChatShareDraftStore`）。 */
typealias ChatShareDraftStore = EventBroadcast<ChatShareDraft>
