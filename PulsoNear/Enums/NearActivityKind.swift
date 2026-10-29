import PulsoLinkCore
import SwiftUI

/**
 * Near 活动类型——全产品唯一权威列表（对应 Android `NearActivityKind`，顺序与 WEB `NEAR_ACTIVITY_TYPE_NAV_ORDER` 一致）。
 * wire 值与 [NearActivityType] 相同。
 */
enum NearActivityKind: String, CaseIterable, Identifiable {
    case mahjong
    case texasHoldem = "texas_holdem"
    case boardGame = "board_game"
    case werewolf
    case scriptMurder = "script_murder"
    case billiards
    case escapeRoom = "escape_room"
    case esports
    case ktv
    case barParty = "bar_party"
    case indoorSocial = "indoor_social"
    case outdoorSocial = "outdoor_social"
    case languageExchange = "language_exchange"
    case bookClub = "book_club"
    case diy

    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .mahjong: "shell_home_module_mahjong"
        case .texasHoldem: "shell_home_module_texas_holdem"
        case .boardGame: "shell_home_module_board_game"
        case .werewolf: "shell_home_module_werewolf"
        case .scriptMurder: "shell_home_module_script_murder"
        case .billiards: "shell_home_module_billiards"
        case .escapeRoom: "shell_home_module_escape_room"
        case .esports: "shell_home_module_esports"
        case .ktv: "shell_home_module_ktv"
        case .barParty: "shell_home_module_bar_party"
        case .indoorSocial: "shell_home_module_indoor_social"
        case .outdoorSocial: "shell_home_module_outdoor_social"
        case .languageExchange: "shell_home_module_language_exchange"
        case .bookClub: "shell_home_module_book_club"
        case .diy: "shell_home_module_diy"
        }
    }

    /** Assets.xcassets 里的活动图（来自 Android drawable）。 */
    var imageName: String {
        switch self {
        case .mahjong: "mahjong"
        case .texasHoldem: "texas_holdem"
        case .boardGame: "board_game"
        case .werewolf: "werewolf"
        case .scriptMurder: "script_murder"
        case .billiards: "billiards"
        case .escapeRoom: "escape_room"
        case .esports: "esports"
        case .ktv: "ktv"
        case .barParty: "bar_party"
        case .indoorSocial: "indoor_social"
        case .outdoorSocial: "outdoor_social"
        case .languageExchange: "language_exchange"
        case .bookClub: "book_club"
        case .diy: "diy"
        }
    }

    /** 能发起和报名（false 的显示即将推出）。 */
    var available: Bool {
        true
    }

    var activityType: NearActivityType {
        NearActivityType.fromWire(rawValue)
    }
}
