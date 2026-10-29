import PulsoLinkCore

struct BadmintonListKey: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var limit = 50
    var offset = 0
    var includeEnded = true
    var endedOnly = false
    var hostedProfileId: String?
    var hostedProfileScope: ProfileKind?
    var buildingId: String?
}

struct MyBadmintonRegistrationsKey: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var limit = 100
    var offset = 0
    var includeEnded = true
    var excludeHosted = false
    /** 一页取全部报名（忽略 limit / offset），给必须全部显示的列表。 */
    var all = false
}

/** 别人主页「参加的活动」（公开接口，与登录身份无关）。 */
struct BadmintonProfileRegistrationsKey: Hashable, Sendable {
    var profileId: String
    var profileScope: ProfileKind = .community
    var limit = 50
    var includeEnded = true
}

struct BadmintonRegsKey: Hashable, Sendable {
    var eventId: String
    var offset = 0
    var limit = 30
}
