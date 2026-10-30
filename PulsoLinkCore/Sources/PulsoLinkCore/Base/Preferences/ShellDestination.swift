import Foundation

/**
 * 主壳可挂载目标（底栏槽位 + Apps 托盘）。
 * 仅无路径参数、可独立打开的叶子页；聊天室 / 活动详情等需 id 的排除。
 */
public enum ShellDestination: String, Codable, CaseIterable, Sendable {
    /** 地图探索。 */
    case explore = "EXPLORE"
    /** 活动与订场：我发起的、我参加的、我的订场（Near：活动与预约）。 */
    case calendar = "CALENDAR"
    /** 附近活动搜索列表。 */
    case search = "SEARCH"
    /** 附近球馆搜索列表。 */
    case venueSearch = "VENUE_SEARCH"
    case create = "CREATE"
    case settings = "SETTINGS"
    case billing = "BILLING"
    /** 消息：会话列表，右上角进通知与社交。 */
    case chatHub = "CHAT_HUB"
    case profile = "PROFILE"
    /** 钱包：会员卡 + 时长包，付款方式 / 收款账户入口。 */
    case wallet = "WALLET"
    /** 课程与私教：我的课程报名，右上角进我的私教（教练面板在私教页里）。 */
    case courses = "COURSES"
    /** 赛事：公开赛事列表与搜索，右上角进我的赛事。 */
    case tournaments = "TOURNAMENTS"
    /** 收藏的球馆与建筑。 */
    case favorites = "FAVORITES"
    /** 论坛：帖子信息流、论坛搜索与我的论坛。 */
    case forum = "FORUM"
    /** 我的地点：我标记的地点申请（原在设置里）。 */
    case placeRequests = "PLACE_REQUESTS"

    /** 活动页与球馆消费页（钱包 / 课程与私教 / 赛事）只属于 community 身份。 */
    private static let communityOnly: Set<ShellDestination> = [
        .calendar, .search, .create, .wallet, .courses, .tournaments,
    ]

    /** 与 Android 一致：按名字大小写不敏感匹配（底栏偏好 JSON 跨端共用）。 */
    public static func fromWire(_ raw: String?) -> ShellDestination? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return ShellDestination(rawValue: trimmed.uppercased())
    }

    /** 该身份在本 App（[supported]，见 `PulsoCoreConfig.shellDestinations`）里可挂载到底栏 / Apps 托盘 / 导航编辑的页面。 */
    public static func available(for kind: ProfileKind, supported: Set<ShellDestination>) -> [ShellDestination] {
        allCases.filter { supported.contains($0) && (kind == .community || !communityOnly.contains($0)) }
    }
}
