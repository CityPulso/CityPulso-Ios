import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

extension ForumSport {
    /** 论坛运动背后的 Loop 运动；「其他」没有。 */
    var sport: LoopSport? { LoopSport.allCases.first { $0.rawValue == rawValue } }

    var labelKey: LocalizedStringKey {
        sport?.labelKey ?? "discussion_forum_type_other"
    }

    var labelResource: String.LocalizationValue {
        sport?.labelResource ?? "discussion_forum_type_other"
    }
}

extension ProfileKind {
    /** 论坛的主办方徽标：平台（官方）、组织或球友（Android `forumBadgeRes`）。 */
    var forumBadgeKey: LocalizedStringKey {
        switch self {
        case .authority: "discussion_badge_official"
        case .organization: "discussion_badge_organization"
        case .community: "discussion_badge_community"
        }
    }
}

/** PulsoLoop 网页地址；分享链接在网页上打开帖子。 */
let loopWebBaseURL = "https://loop.citypulso.com"

/** 帖子的公开网页（分享面板发它）。 */
func postShareURL(_ postId: String) -> URL {
    URL(string: "\(loopWebBaseURL)/panel/discussion/post-detail/\(postId)")!
}

extension PostKind {
    /** 帖子类型标签的颜色（WEB 同款）。 */
    var tone: Color {
        switch self {
        case .discussion: Color(argb: 0xFF0090FF)
        case .playersWanted: Color(argb: 0xFF30A46C)
        case .match: Color(argb: 0xFFF76B15)
        case .eventRecap: Color(argb: 0xFF8E4EC6)
        case .tips: Color(argb: 0xFFD6A100)
        case .question: Color(argb: 0xFF00A2C7)
        case .gear: Color(argb: 0xFF8B8D98)
        }
    }
}

extension PostLinkType {
    /** 链接类型标签的颜色：活动橙、球馆绿、帖子蓝、建筑青（WEB 同款）。 */
    var tone: Color {
        switch self {
        case .post: Color(argb: 0xFF0090FF)
        case .event: Color(argb: 0xFFF76B15)
        case .venue: Color(argb: 0xFF30A46C)
        case .building: Color(argb: 0xFF12A594)
        }
    }

    /** 「还有 N 个链接」后面的分类计数（「1 个活动」）。 */
    func countText(_ count: Int) -> String {
        switch self {
        case .post: localizedFormat("discussion_link_count_post", count)
        case .event: localizedFormat("discussion_link_count_event", count)
        case .venue: localizedFormat("discussion_link_count_venue", count)
        case .building: localizedFormat("discussion_link_count_building", count)
        }
    }
}
