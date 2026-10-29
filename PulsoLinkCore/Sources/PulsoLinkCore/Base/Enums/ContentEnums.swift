import Foundation

/*
 * 产品事件类型分类（偏好 / 模块开关用）——与 PulsoLink-Package `enums/content.ts` 对齐。
 * Near 活动类型与 Loop 运动类型是两套独立偏好列表。
 */

/** Near 活动类型（每种一套独立表）。 */
public enum NearActivityType: String, WireEnum {
    case mahjong
    case texasHoldem = "texas_holdem"
    case boardGame = "board_game"
    case billiards
    case indoorSocial = "indoor_social"
    case scriptMurder = "script_murder"
    case bookClub = "book_club"
    case languageExchange = "language_exchange"
    case outdoorSocial = "outdoor_social"
    case diy
    case werewolf
    case escapeRoom = "escape_room"
    case esports
    case barParty = "bar_party"
    case ktv

    public static let fallback: NearActivityType = .boardGame
}

/** Loop 活动类型（运动）。 */
public enum LoopEventType: String, WireEnum {
    case badminton, tennis, pickleball, basketball, football, baseball, golf, hiking, fishing, ski
    case tableTennis = "table_tennis"

    public static let fallback: LoopEventType = .badminton
}
