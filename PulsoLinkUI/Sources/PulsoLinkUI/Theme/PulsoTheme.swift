import PulsoLinkCore
import SwiftUI

/*
 * 主题入口（对应 Android `PulsoTheme`）：服务端主题偏好解成 [PulsoPalette]（强调色 / 灰阶 / 圆角 / 面板）放进环境，
 * Pulso 组件都从它取色取形；强调色同时作为系统 `.tint`，浅 / 深色走 `.preferredColorScheme`。
 * 字体用系统 SF 与动态字体（iOS 系统设置管字号）。
 */

extension ThemeAccentColor {
    /** Radix 色阶第 9 阶（实心强调色，与 Android / WEB 同值）。 */
    public var color: Color {
        let rgb: UInt32 = switch self {
        case .gray: 0x8D8D8D
        case .gold: 0x978365
        case .bronze: 0xA18072
        case .brown: 0xAD7F58
        case .yellow: 0xFFE629
        case .amber: 0xFFC53D
        case .orange: 0xF76B15
        case .tomato: 0xE54D2E
        case .red: 0xE5484D
        case .ruby: 0xE54666
        case .crimson: 0xE93D82
        case .pink: 0xD6409F
        case .plum: 0xAB4ABA
        case .purple: 0x8E4EC6
        case .violet: 0x6E56CF
        case .iris: 0x5B5BD6
        case .indigo: 0x3E63DD
        case .blue: 0x0090FF
        case .cyan: 0x00A2C7
        case .teal: 0x12A594
        case .jade: 0x29A383
        case .green: 0x30A46C
        case .grass: 0x46A758
        case .lime: 0xBDEE63
        case .mint: 0x86EAD4
        case .sky: 0x7CE2FE
        }
        return Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension ThemeAppearance {
    /** nil = 跟随系统。 */
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /** 把主题偏好套到整棵视图树上。 */
    public func pulsoTheme(_ settings: PulsoThemeSettings) -> some View {
        tint(settings.accent.color)
            // 还有页面直接用 `Color.accentColor`（读环境强调色，不跟 `.tint`）；对齐时逐页换成色板。
            .accentColor(settings.accent.color)
            .environment(\.pulsoPalette, PulsoPalette(settings))
            .preferredColorScheme(settings.appearance.colorScheme)
            .onChange(of: settings, initial: true) { _, settings in PulsoUIKitAppearance.apply(PulsoPalette(settings)) }
    }
}
