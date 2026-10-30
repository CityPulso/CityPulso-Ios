import Foundation

/**
 * 底栏图标组：选中 / 未选中成对，用户只能整组替换，不能单改某一态。
 * wire 值是 Android 枚举名（UPPER_SNAKE），底栏偏好 JSON 两端共用。
 */
public enum ShellNavIconPack: String, Codable, CaseIterable, Sendable {
    case home = "HOME"
    case map = "MAP"
    case calendar = "CALENDAR"
    case explore = "EXPLORE"
    case search = "SEARCH"
    case social = "SOCIAL"
    case create = "CREATE"
    case settings = "SETTINGS"
    case billing = "BILLING"
    case notifications = "NOTIFICATIONS"
    case chat = "CHAT"
    case profile = "PROFILE"
    case event = "EVENT"
    case place = "PLACE"
    case sports = "SPORTS"
    case wallet = "WALLET"
    case school = "SCHOOL"
    case book = "BOOK"
    case trophy = "TROPHY"
    case booking = "BOOKING"
    case favorite = "FAVORITE"
    case forum = "FORUM"

    /** 与 Android 一致：按名字大小写不敏感匹配。 */
    public static func fromWire(_ raw: String?) -> ShellNavIconPack? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return ShellNavIconPack(rawValue: trimmed.uppercased())
    }
}

extension ShellDestination {
    /** 某挂载页的默认图标组（未自定义时用）。 */
    public var defaultIconPack: ShellNavIconPack {
        switch self {
        case .explore: .explore
        case .calendar: .calendar
        case .search: .sports
        case .venueSearch: .place
        case .create: .create
        case .settings: .settings
        case .billing: .billing
        case .chatHub: .chat
        case .profile: .profile
        case .wallet: .wallet
        case .courses: .book
        case .coaching: .school
        case .tournaments: .trophy
        case .favorites: .favorite
        case .forum: .forum
        }
    }
}
