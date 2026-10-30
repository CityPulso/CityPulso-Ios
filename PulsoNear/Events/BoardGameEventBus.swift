import PulsoLinkCore

/** 桌游写操作后的失效事件（对应 Android `BoardGameEventBus`、WEB `events/boardGame.ts`）：日历、资料活动等重拉。 */
enum BoardGameEvent: Sendable {
    case invalidate
}

typealias BoardGameEventBus = EventBroadcast<BoardGameEvent>

extension EventBroadcast where Event == BoardGameEvent {
    func invalidate() {
        emit(.invalidate)
    }
}
