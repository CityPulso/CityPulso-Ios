import BetterCodable
import Foundation

/* 主题偏好闭集枚举——wire 值与 PulsoLink-Package `enums/theme.ts` 逐一对齐，与服务端 profile preference JSON 共用。 */

/** 外观偏好：浅色 / 深色 / 跟随系统（对应 AppearanceEnum）。 */
public enum ThemeAppearance: String, WireEnum {
    case light
    case dark
    case system

    public static let fallback: ThemeAppearance = .system
}

/** Radix 强调色（对应 AccentColorEnum，26 色全量）。 */
public enum ThemeAccentColor: String, WireEnum {
    case gray, gold, bronze, brown, yellow, amber, orange, tomato, red, ruby, crimson, pink, plum
    case purple, violet, iris, indigo, blue, cyan, teal, jade, green, grass, lime, mint, sky

    // 全产品默认强调色（与 Package DEFAULT_ACCENT_COLOR / DEFAULT_RADIX_ACCENT 同步）
    public static let fallback: ThemeAccentColor = .tomato
}

/** Radix 中性灰（对应 GrayColorEnum；auto 由 accent 推导）。 */
public enum ThemeGrayColor: String, WireEnum {
    case auto, gray, mauve, slate, sage, olive, sand

    public static let fallback: ThemeGrayColor = .slate
}

/** Radix 圆角档位（对应 RadiusEnum；平台映射 none=Linux / small=Android / medium=Other / large=Windows / full=iOS）。 */
public enum ThemeRadius: String, WireEnum {
    case none, small, medium, large, full

    public static let fallback: ThemeRadius = .medium
}

/** Radix 缩放比例（对应 ScalingEnum）。 */
public enum ThemeScaling: String, WireEnum {
    case scale90 = "90%"
    case scale95 = "95%"
    case scale100 = "100%"
    case scale105 = "105%"
    case scale110 = "110%"

    public static let fallback: ThemeScaling = .scale100

    public var factor: Double {
        switch self {
        case .scale90: 0.9
        case .scale95: 0.95
        case .scale100: 1.0
        case .scale105: 1.05
        case .scale110: 1.1
        }
    }
}

/** Radix 面板背景（对应 PanelBackgroundEnum）。 */
public enum ThemePanelBackground: String, WireEnum {
    case solid, translucent

    public static let fallback: ThemePanelBackground = .translucent
}

/** UI 正文字体族（对应 ThemeFontFamilyEnum）。 */
public enum ThemeFontFamily: String, WireEnum {
    case system
    case ibmPlex = "ibm-plex"
    case noto
    case sourceSans = "source-sans"

    public static let fallback: ThemeFontFamily = .system
}

/**
 * 完整主题偏好（对应 WEB `ResolvedThemePreference` + Radix `<Theme>` props）。
 * 默认值与 WEB 一致：system / tomato / slate / medium / 100% / translucent / system。
 */
public struct PulsoThemeSettings: Codable, Sendable, Hashable {
    @DefaultWire<ThemeAppearance> public var appearance: ThemeAppearance
    @DefaultWire<ThemeAccentColor> public var accent: ThemeAccentColor
    @DefaultWire<ThemeGrayColor> public var gray: ThemeGrayColor
    @DefaultWire<ThemeRadius> public var radius: ThemeRadius
    @DefaultWire<ThemeScaling> public var scaling: ThemeScaling
    @DefaultWire<ThemePanelBackground> public var panelBackground: ThemePanelBackground
    @DefaultWire<ThemeFontFamily> public var fontFamily: ThemeFontFamily

    public init(
        appearance: ThemeAppearance = .fallback,
        accent: ThemeAccentColor = .fallback,
        gray: ThemeGrayColor = .fallback,
        radius: ThemeRadius = .fallback,
        scaling: ThemeScaling = .fallback,
        panelBackground: ThemePanelBackground = .fallback,
        fontFamily: ThemeFontFamily = .fallback
    ) {
        self.appearance = appearance
        self.accent = accent
        self.gray = gray
        self.radius = radius
        self.scaling = scaling
        self.panelBackground = panelBackground
        self.fontFamily = fontFamily
    }

    public static let `default` = PulsoThemeSettings()
}
