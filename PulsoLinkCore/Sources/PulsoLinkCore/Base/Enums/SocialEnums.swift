import Foundation

/* 社交域闭集枚举——wire 值与 PulsoLink-Package `enums/social.ts` 逐一对齐。 */

/** 谁可以向我发好友请求。 */
public enum SocialFriendRequestPolicy: String, WireEnum {
    case everyone
    case peopleFollowedByMe = "people_followed_by_me"
    case mutualFollows = "mutual_follows"
    case nobody

    public static let fallback: SocialFriendRequestPolicy = .everyone
}

/** 私信受众（可多选；空 = 没有人）。 */
public enum SocialDirectMessagePolicy: String, WireEnum {
    case strangers
    case friends
    case peopleFollowedByMe = "people_followed_by_me"
    case peopleFollowingMe = "people_following_me"

    public static let fallback: SocialDirectMessagePolicy = .friends
}

/** 群邀请受众（可多选；空 = 没有人）。 */
public enum SocialGroupInvitePolicy: String, WireEnum {
    case strangers
    case friends
    case peopleFollowedByMe = "people_followed_by_me"
    case peopleFollowingMe = "people_following_me"

    public static let fallback: SocialGroupInvitePolicy = .friends
}
