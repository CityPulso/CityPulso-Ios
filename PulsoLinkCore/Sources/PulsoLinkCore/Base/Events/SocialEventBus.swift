/** 社交域缓存失效事件（Android `SocialEvent`，WEB `events/social.ts`）。 */
public enum SocialEvent: Sendable, Equatable {
    case invalidateStats
    case invalidateFollowing
    case invalidateFollowers
    case invalidateFriends
    case invalidateBlocked
    /** [direction] 为 nil 表示双向都失效。 */
    case invalidateFriendRequests(SocialFriendRequestDirection?)
    case invalidatePrivacySettings
    case invalidateRelationStatus

    /** 好友请求失效：带方向的只命中同方向或不分方向的列表。 */
    public var isFriendRequests: Bool {
        if case .invalidateFriendRequests = self { true } else { false }
    }
}

public typealias SocialEventBus = EventBroadcast<SocialEvent>

/* ------------------------------ 级联 helper（对应 Android `SocialEventBus` 方法） ------------------------------ */

public extension EventBroadcast where Event == SocialEvent {
    /** 关注 / 取关后：数字 + 关注 + 粉丝 + 关系状态。 */
    func invalidateFollowRelation(refreshFollowing: Bool = true) {
        emit(.invalidateStats)
        if refreshFollowing { emit(.invalidateFollowing) }
        emit(.invalidateFollowers)
        emit(.invalidateRelationStatus)
    }

    /** 拉黑 / 解除拉黑后：服务端会删好友、撤销待处理请求、双向取关，所有可能增减目标的列表都刷新。 */
    func invalidateBlockRelation() {
        emit(.invalidateBlocked)
        emit(.invalidateStats)
        emit(.invalidateRelationStatus)
        emit(.invalidateFriends)
        emit(.invalidateFollowing)
        emit(.invalidateFollowers)
        emit(.invalidateFriendRequests(.incoming))
        emit(.invalidateFriendRequests(.outgoing))
    }

    /** 好友请求被接受后：收到的请求 + 好友 + 数字 + 关系状态。 */
    func invalidateFriendRequestAccepted() {
        emit(.invalidateFriendRequests(.incoming))
        emit(.invalidateFriends)
        emit(.invalidateStats)
        emit(.invalidateRelationStatus)
    }

    /** 搜索页关系操作后全量刷新。 */
    func invalidateSearchRelations() {
        emit(.invalidateRelationStatus)
        invalidateFollowRelation()
        emit(.invalidateFriends)
        emit(.invalidateBlocked)
        emit(.invalidateFriendRequests(.incoming))
        emit(.invalidateFriendRequests(.outgoing))
    }
}
