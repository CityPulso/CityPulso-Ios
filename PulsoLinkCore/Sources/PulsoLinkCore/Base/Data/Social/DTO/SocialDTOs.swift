import BetterCodable
import Foundation

/* 社交域 DTO——与 PulsoLink-Package `types/domain/social` 逐一对齐（其余部分随社交页移植）。 */

/** GET / PUT /social/me/setting/privacy 响应。 */
public struct PrivacySettings: Codable, Sendable, Hashable {
    public let profileId: String
    public let profileScope: ProfileKind
    public var friendRequestPolicy: SocialFriendRequestPolicy
    @DefaultEmptyArray public var directMessagePolicy: [SocialDirectMessagePolicy]
    @DefaultEmptyArray public var groupInvitePolicy: [SocialGroupInvitePolicy]
    public var showFriendList: Bool
    public var showBlockList: Bool
    public var showFollowingList: Bool
    public var showFollowerList: Bool
    public let updatedAt: String
}

/** PUT /social/me/setting/privacy 请求（整份替换）。 */
public struct UpdatePrivacySettingsRequest: Encodable, Sendable {
    public let friendRequestPolicy: SocialFriendRequestPolicy
    public let directMessagePolicy: [SocialDirectMessagePolicy]
    public let groupInvitePolicy: [SocialGroupInvitePolicy]
    public let showFriendList: Bool
    public let showBlockList: Bool
    public let showFollowingList: Bool
    public let showFollowerList: Bool

    public init(_ settings: PrivacySettings) {
        friendRequestPolicy = settings.friendRequestPolicy
        directMessagePolicy = settings.directMessagePolicy
        groupInvitePolicy = settings.groupInvitePolicy
        showFriendList = settings.showFriendList
        showBlockList = settings.showBlockList
        showFollowingList = settings.showFollowingList
        showFollowerList = settings.showFollowerList
    }
}
