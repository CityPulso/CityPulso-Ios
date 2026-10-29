import PulsoLinkCore
import SwiftUI

/**
 * Loop 运动类型——全产品唯一权威列表（对应 Android `LoopSport`，顺序与发起活动选运动一致）。
 * wire 值与 [LoopEventType] 相同。
 */
enum LoopSport: String, CaseIterable, Identifiable {
    case badminton
    case tennis
    case pickleball
    case basketball
    case football
    case baseball
    case golf
    case hiking
    case fishing
    case ski
    case tableTennis = "table_tennis"

    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .badminton: "shell_home_module_badminton"
        case .tennis: "shell_home_module_tennis"
        case .pickleball: "shell_home_module_pickleball"
        case .basketball: "shell_home_module_basketball"
        case .football: "shell_home_module_football"
        case .baseball: "shell_home_module_baseball"
        case .golf: "shell_home_module_golf"
        case .hiking: "shell_home_module_hiking"
        case .fishing: "shell_home_module_fishing"
        case .ski: "shell_home_module_ski"
        case .tableTennis: "shell_home_module_table_tennis"
        }
    }

    /** Assets.xcassets 里的运动图（来自 Android drawable）。 */
    var imageName: String {
        switch self {
        case .badminton: "badminton"
        case .tennis: "tennis"
        case .pickleball: "pickleball"
        case .basketball: "basketball"
        case .football: "football"
        case .baseball: "baseball"
        case .golf: "golf"
        case .hiking: "hiking"
        case .fishing: "fishing"
        case .ski: "ski"
        case .tableTennis: "table_tennis"
        }
    }

    /** 能发起和报名（false 的显示即将推出）。 */
    var available: Bool {
        true
    }

    /** 发起活动时长的快捷选项（分钟）。 */
    var durationPresetsMinutes: [Int] {
        switch self {
        case .badminton: [60, 120, 180, 240]
        case .tennis: [60, 120, 180, 240]
        case .pickleball: [60, 120, 180, 240]
        case .basketball: [60, 120, 180]
        case .football: [60, 90, 120]
        case .baseball: [120, 180, 240]
        case .golf: [180, 300, 360]
        case .hiking: [120, 240, 360, 480]
        case .fishing: [240, 360, 480]
        case .ski: [240, 360, 480]
        case .tableTennis: [60, 120, 180]
        }
    }

    /** 新活动的默认时长（分钟）。 */
    var defaultDurationMinutes: Int {
        switch self {
        case .badminton: 120
        case .tennis: 120
        case .pickleball: 120
        case .basketball: 120
        case .football: 90
        case .baseball: 180
        case .golf: 300
        case .hiking: 240
        case .fishing: 240
        case .ski: 480
        case .tableTennis: 120
        }
    }

    var eventType: LoopEventType {
        LoopEventType.fromWire(rawValue)
    }
}
