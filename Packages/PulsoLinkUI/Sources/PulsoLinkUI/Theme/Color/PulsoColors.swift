import PulsoLinkCore
import SwiftUI

/**
 * Radix 色阶 → 语义颜色（与 Android `PulsoColorSchemes` 的 M3 槽位映射同一套规则）：
 * - step9 solid 背景 → primary（onPrimary 用官方 accent contrast 色）；step10 → secondary
 * - step3/4 组件底色 → container；step11 低对比文本 → onContainer
 * - gray1 应用底 → background / surface；gray2..4 → surfaceContainer 系列
 * - gray6/8 边框 → outlineVariant / outline；gray11/12 文本 → onSurfaceVariant / onSurface
 * - error 一律取 Radix red 色阶
 */
public struct PulsoColors: Sendable, Equatable {
    public let accent: RadixScale
    public let gray: RadixScale

    public let primary: Color
    public let onPrimary: Color
    public let primaryContainer: Color
    public let onPrimaryContainer: Color
    public let secondary: Color
    public let secondaryContainer: Color
    public let onSecondaryContainer: Color
    public let error: Color
    public let onError: Color
    public let errorContainer: Color
    public let onErrorContainer: Color
    public let background: Color
    public let onBackground: Color
    public let surface: Color
    public let onSurface: Color
    public let onSurfaceVariant: Color
    public let surfaceContainerLowest: Color
    public let surfaceContainerLow: Color
    public let surfaceContainer: Color
    public let surfaceContainerHigh: Color
    public let surfaceContainerHighest: Color
    public let outline: Color
    public let outlineVariant: Color

    public init(accent accentColor: ThemeAccentColor, gray grayColor: ThemeGrayColor, dark: Bool) {
        let a = RadixColorScales.accent(accentColor, dark: dark)
        let g = RadixColorScales.gray(resolveGrayColor(grayColor, accent: accentColor), dark: dark)
        let red = dark ? RadixColorScales.redDark : RadixColorScales.redLight
        let contrast = Self.accentContrast(accentColor)

        accent = a
        gray = g
        primary = a.step(9)
        onPrimary = contrast
        primaryContainer = a.step(4)
        onPrimaryContainer = a.step(11)
        secondary = a.step(10)
        secondaryContainer = a.step(3)
        onSecondaryContainer = a.step(11)
        error = red.step(9)
        onError = .white
        errorContainer = red.step(3)
        onErrorContainer = red.step(11)
        background = g.step(1)
        onBackground = g.step(12)
        surface = g.step(1)
        onSurface = g.step(12)
        onSurfaceVariant = g.step(11)
        surfaceContainerLowest = dark ? g.step(1) : .white
        surfaceContainerLow = g.step(2)
        surfaceContainer = g.step(2)
        surfaceContainerHigh = g.step(3)
        surfaceContainerHighest = g.step(4)
        outline = g.step(8)
        outlineVariant = g.step(6)
    }

    /** accent step9 上的文字色——与 @radix-ui/themes `--{accent}-contrast` 官方值一致。 */
    public static func accentContrast(_ accent: ThemeAccentColor) -> Color {
        switch accent {
        case .amber, .yellow: Color(rgb: 0x21201C)
        case .lime: Color(rgb: 0x1D211C)
        case .mint: Color(rgb: 0x1A211E)
        case .sky: Color(rgb: 0x1C2024)
        default: .white
        }
    }
}
