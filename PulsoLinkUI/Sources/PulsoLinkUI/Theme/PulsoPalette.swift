import PulsoLinkCore
import SwiftUI

/**
 * 当前主题解出来的色板与形状（对应 Android `PulsoTheme` 提供的 LocalPulsoAccentScale / LocalPulsoGrayScale /
 * LocalPulsoShapes / LocalPulsoPanelStyle）：组件一律从这里取色，不写死系统色。
 *
 * 颜色角色与 Android `PulsoColorSchemes` 同一套映射：
 * - accent step9 → 实心按钮、选中；step3 / step11 → 柔和底和字；step8 → 描边
 * - gray step1 → 页面底；step2 → 面板（translucent 时 80%）；step6 / step8 → 分隔线 / 描边；step11 / step12 → 次要字 / 正文
 */
public struct PulsoPalette: Sendable {
    public let accent: RadixScale
    public let gray: RadixScale
    /** accent step9 上的文字色（Radix `--{accent}-contrast`）。 */
    public let onAccent: Color
    public let radius: ThemeRadius
    public let panelBackground: ThemePanelBackground

    public init(_ settings: PulsoThemeSettings) {
        accent = RadixScale(settings.accent)
        gray = RadixScale(settings.gray.resolved(for: settings.accent))
        onAccent = settings.accent.contrast
        radius = settings.radius
        panelBackground = settings.panelBackground
    }

    public static let `default` = PulsoPalette(.default)

    // MARK: 颜色角色

    public var background: Color { gray.step(1) }
    public var text: Color { gray.step(12) }
    public var secondaryText: Color { gray.step(11) }
    public var outline: Color { gray.step(8) }
    public var outlineVariant: Color { gray.step(6) }
    public var error: Color { RadixScale.red.step(9) }
    /** 卡片 / 分组面板底色：translucent 是 gray2 @ 0.8，solid 不透明（Android `pulsoPanelColor`）。 */
    public var panel: Color { panelBackground == .translucent ? gray.step(2).opacity(0.8) : gray.step(2) }

    // MARK: 圆角（Radix --radius-1…6 = 3/4/6/8/12/16 × 档位系数）

    private var radiusFactor: CGFloat {
        switch radius {
        case .none: 0
        case .small: 0.75
        case .medium: 1
        case .large, .full: 1.5
        }
    }

    public func radius(_ step: Int) -> CGFloat {
        [3, 4, 6, 8, 12, 16][step - 1] * radiusFactor
    }

    /** 按钮、单行输入框、分段、标签：full 档是胶囊。 */
    public var controlShape: AnyShape { radius == .full ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: radius(3), style: .continuous)) }
    /** 小标签、色块。 */
    public var chipShape: AnyShape { radius == .full ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: radius(2), style: .continuous)) }
    /** 卡片、列表面板（full 档 r6，其余 r4）。 */
    public var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: radius == .full ? radius(6) : radius(4), style: .continuous) }
    /** 卡片里嵌套的缩略图、格子。 */
    public var innerShape: RoundedRectangle { RoundedRectangle(cornerRadius: radius(2), style: .continuous) }
    /** 多行输入框。 */
    public var textAreaShape: RoundedRectangle { RoundedRectangle(cornerRadius: radius(3), style: .continuous) }
}

/** 尺寸 token（Android `PulsoDimensions`，与 WEB `--space-1…9` 同刻度）。 */
public enum PulsoSpace {
    public static let half: CGFloat = 2
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 24
    public static let s6: CGFloat = 32
    public static let s7: CGFloat = 40
    public static let s8: CGFloat = 48
    public static let s9: CGFloat = 64
}

/** 输入框 / 按钮共用的高度档（Android `PulsoControlSize`）。 */
public enum PulsoControlSize: Sendable {
    case small, compact, comfortable, prominent

    public var height: CGFloat {
        switch self {
        case .small: 32
        case .compact: 40
        case .comfortable: 48
        case .prominent: 56
        }
    }
}

/** 细线宽度：边框与分隔线。 */
public let pulsoHairline: CGFloat = 0.5
/** 选中 / 强调描边。 */
public let pulsoStrokeEmphasis: CGFloat = 1

extension EnvironmentValues {
    @Entry public var pulsoPalette: PulsoPalette = .default
    /** 页面级默认控件高度（登录 / 注册是 comfortable，其余 compact）。 */
    @Entry public var pulsoControlSize: PulsoControlSize = .compact
}

extension RadixScale {
    init(_ accent: ThemeAccentColor) {
        self = RadixScale(rawValue: accent.rawValue) ?? .tomato
    }

    init(_ gray: ThemeGrayColor) {
        self = RadixScale(rawValue: gray.rawValue) ?? .slate
    }
}

extension ThemeGrayColor {
    /** gray=auto 按 accent 配对中性灰（Radix `getMatchingGrayColor`，Android `resolveGrayColor`）。 */
    func resolved(for accent: ThemeAccentColor) -> ThemeGrayColor {
        guard self == .auto else { return self }
        return switch accent {
        case .tomato, .red, .ruby, .crimson, .pink, .plum, .purple, .violet: .mauve
        case .iris, .indigo, .blue, .sky, .cyan: .slate
        case .teal, .jade, .mint, .green: .sage
        case .grass, .lime: .olive
        case .yellow, .amber, .orange, .brown, .gold, .bronze: .sand
        case .gray: .gray
        }
    }
}

extension ThemeAccentColor {
    /** step9 上的文字色（与 @radix-ui/themes `--{accent}-contrast` 一致）。 */
    var contrast: Color {
        switch self {
        case .amber, .yellow: Color(red: 0x21 / 255, green: 0x20 / 255, blue: 0x1C / 255)
        case .lime: Color(red: 0x1D / 255, green: 0x21 / 255, blue: 0x1C / 255)
        case .mint: Color(red: 0x1A / 255, green: 0x21 / 255, blue: 0x1E / 255)
        case .sky: Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x24 / 255)
        default: .white
        }
    }
}
