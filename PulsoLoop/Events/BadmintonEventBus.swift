import PulsoLinkCore

/** 羽毛球写操作后的失效事件（对应 Android `BadmintonEventBus`、WEB `events/badminton.ts`）：日历、资料活动等重拉。 */
enum BadmintonEvent: Sendable {
    case invalidate
}

typealias BadmintonEventBus = EventBroadcast<BadmintonEvent>

extension EventBroadcast where Event == BadmintonEvent {
    func invalidate() {
        emit(.invalidate)
    }
}
