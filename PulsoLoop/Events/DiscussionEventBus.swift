import PulsoLinkCore

/** 任何论坛写操作后让论坛 / 帖子 / 评论查询重拉（Android `DiscussionEventBus`，WEB `events/discussion.ts`）。 */
enum DiscussionEvent: Sendable {
    case invalidate
}

typealias DiscussionEventBus = EventBroadcast<DiscussionEvent>

extension EventBroadcast where Event == DiscussionEvent {
    func invalidate() {
        emit(.invalidate)
    }
}
