import Foundation
import Observation
import PulsoLinkCore

/** 娱邻接的深链 scheme（跃圈打开卡片时用，见 Info.plist 的 URL Types）。 */
let ownDeepLinkScheme = "youneary"

/** 跃圈：聊天里跃圈的卡片在那边打开。 */
let peerApp = SiblingApp(scheme: "youloopy", webOrigin: "https://pulsoloop.com")

/**
 * 别的 App（跃圈）通过 `youneary://open/<path>` 打开的页面；路径和 pulsonear.com 一样。不认识的路径什么都不开
 * （Android `NearDeepLinks`）。
 */
enum NearDeepLinks {
    static func parse(_ url: URL) -> NearRoute? {
        guard let link = DeepLinkPath(url, scheme: ownDeepLinkScheme), link.segments.first == "panel" else { return nil }
        let parts = link.segments
        switch (parts.count, parts.count > 1 ? parts[1] : "") {
        case (4, "activity-detail"):
            return .activity(activityType: NearActivityKind.fromWire(parts[2]), activityId: parts[3])
        case (3, "venue-detail"):
            return .venue(venueId: parts[2], sheet: nil)
        case (3, "venue-book"):
            if let type = VenueActivityType.allCases.first(where: { $0.rawValue == link.query["activityType"] }) {
                return .venueBook(venueId: parts[2], activityType: type)
            }
            return .venue(venueId: parts[2], sheet: nil)
        case (3, "building-detail"):
            return .building(buildingId: parts[2])
        case (4, "discussion") where parts[2] == "post-detail":
            return .post(postId: parts[3])
        case (4, "discussion") where parts[2] == "forum-detail":
            return .forum(forumId: parts[3])
        default:
            return nil
        }
    }
}

/**
 * 留住深链打开的页面，等登录后的导航起来再打开（冷启动时链接先到）；主界面取走后清空（Android `NearDeepLinkInbox`）。
 */
@MainActor
@Observable
final class NearDeepLinkInbox {
    static let shared = NearDeepLinkInbox()

    private(set) var pending: NearRoute?

    /** 认识的链接存下来，返回 true；别的（比如 Google 登录回跳）返回 false。 */
    @discardableResult
    func offer(_ url: URL) -> Bool {
        guard let route = NearDeepLinks.parse(url) else { return false }
        pending = route
        return true
    }

    func take() -> NearRoute? {
        defer { pending = nil }
        return pending
    }
}

extension ChatSharedCardContent {
    /** 卡片属于跃圈：按钮交给跃圈，不在这里打开。场馆建筑两个 App 都有。 */
    var isPeer: Bool { product != nil && product != .near }
}

/** 卡片页面的路径，两个 App 的网站和深链一样（`/panel/...`）；缺页面要的东西时 nil（Android `chatCardPath`）。 */
func chatCardPath(_ type: MessageType, _ card: ChatSharedCardContent) -> String? {
    let id = card.targetId
    switch type {
    case .eventShare:
        guard let subtype = card.subtype, !subtype.isEmpty else { return nil }
        return card.isPeer ? "/panel/event-detail/\(subtype)/\(id)" : "/panel/activity-detail/\(subtype)/\(id)"
    case .venueShare: return "/panel/venue-detail/\(id)"
    case .buildingShare: return "/panel/building-detail/\(id)"
    case .postShare: return "/panel/discussion/post-detail/\(id)"
    case .forumShare: return "/panel/discussion/forum-detail/\(id)"
    default: return nil
    }
}

/** 门店卡片的预约页，停在发的人选的门店类型（娱邻）或运动（跃圈）。 */
func chatVenueBookPath(_ card: ChatSharedCardContent) -> String {
    let base = "/panel/venue-book/\(card.targetId)"
    guard let subtype = card.subtype, !subtype.isEmpty else { return base }
    return card.product == .near ? "\(base)?activityType=\(subtype)" : "\(base)?sport=\(subtype)"
}
