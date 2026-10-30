import PulsoLinkCore
import SwiftUI

extension ForumActivityType {
    /** 论坛活动类型背后的 Near 活动类型；「其他」没有。 */
    var activityType: NearActivityKind? { NearActivityKind.allCases.first { $0.rawValue == rawValue } }

    var labelKey: LocalizedStringKey {
        activityType?.labelKey ?? "discussion_forum_type_other"
    }

    var labelResource: String.LocalizationValue {
        activityType?.labelResource ?? "discussion_forum_type_other"
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

/** PulsoNear 网页地址；分享链接在网页上打开帖子。 */
let loopWebBaseURL = "https://loop.citypulso.com"

/** 帖子的公开网页（分享面板发它）。 */
func postShareURL(_ postId: String) -> URL {
    URL(string: "\(loopWebBaseURL)/panel/discussion/post-detail/\(postId)")!
}

/** 帖子卡片怎么放照片：没有、一张放在文字旁、一排小图（Android `PostMediaLayout`）。 */
enum PostMediaLayout {
    case none
    case single
    case row

    /** 一排最多几张，最后一张写「+N」。 */
    static let rowTiles = 3

    init(imageCount: Int, previewIds: [String]) {
        if imageCount <= 0 || previewIds.isEmpty {
            self = .none
        } else if imageCount == 1 {
            self = .single
        } else {
            self = .row
        }
    }
}

/** 一排里放不下的照片数。 */
func hiddenPhotoCount(_ imageCount: Int, _ previewIds: [String]) -> Int {
    max(0, imageCount - min(previewIds.count, PostMediaLayout.rowTiles))
}

extension PostKind {
    /** 帖子类型标签的颜色（WEB 同款）。 */
    var tone: Color {
        switch self {
        case .discussion: Color(argb: 0xFF0090FF)
        case .playersWanted: Color(argb: 0xFF30A46C)
        case .match: Color(argb: 0xFFF76B15)
        case .activityRecap: Color(argb: 0xFF8E4EC6)
        case .tips: Color(argb: 0xFFD6A100)
        case .question: Color(argb: 0xFF00A2C7)
        case .gear: Color(argb: 0xFF8B8D98)
        }
    }
}
