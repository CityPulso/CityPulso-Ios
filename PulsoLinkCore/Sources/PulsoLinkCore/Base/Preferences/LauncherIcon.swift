import Foundation

/**
 * 桌面图标套图（存 android preference，iOS 共用）。
 * 独立于 ThemeAppearance / 系统深浅色；以后按套图加档，不是 light/dark/system。
 */
public enum LauncherIcon: String, WireEnum {
    case `default`
    case dark

    public static let fallback: LauncherIcon = .default
}
