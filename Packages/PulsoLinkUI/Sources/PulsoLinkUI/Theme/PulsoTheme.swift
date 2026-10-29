import PulsoLinkCore
import SwiftUI

/** 已解析的整套主题（对应 Android `PulsoTheme` 提供的各个 CompositionLocal）。 */
public struct PulsoResolvedTheme: Sendable, Equatable {
    public let settings: PulsoThemeSettings
    public let isDark: Bool
    public let colors: PulsoColors
    public let dimensions: PulsoDimensions
    public let shapes: PulsoShapeSet

    public init(settings: PulsoThemeSettings, isDark: Bool) {
        self.settings = settings
        self.isDark = isDark
        colors = PulsoColors(accent: settings.accent, gray: settings.gray, dark: isDark)
        dimensions = PulsoDimensions(scaling: settings.scaling)
        shapes = PulsoShapeSet(radius: settings.radius)
    }

    public static let `default` = PulsoResolvedTheme(settings: .default, isDark: false)
}

extension EnvironmentValues {
    @Entry public var pulsoTheme: PulsoResolvedTheme = .default
}

/**
 * CityPulso 主题入口（对应 WEB Radix `<Theme appearance accentColor grayColor radius scaling panelBackground>`）：
 * [PulsoThemeSettings] → 颜色 + 尺寸 + 形状，写进环境；明暗跟随设置（system 档跟随系统）。
 */
struct PulsoThemeModifier: ViewModifier {
    let settings: PulsoThemeSettings
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let isDark = switch settings.appearance {
        case .system: systemScheme == .dark
        case .light: false
        case .dark: true
        }
        let theme = PulsoResolvedTheme(settings: settings, isDark: isDark)
        content
            .environment(\.pulsoTheme, theme)
            .tint(theme.colors.primary)
            .preferredColorScheme(settings.appearance == .system ? nil : (isDark ? .dark : .light))
            .animation(.easeInOut(duration: 0.25), value: theme)
    }
}

extension View {
    public func pulsoTheme(_ settings: PulsoThemeSettings) -> some View {
        modifier(PulsoThemeModifier(settings: settings))
    }
}
