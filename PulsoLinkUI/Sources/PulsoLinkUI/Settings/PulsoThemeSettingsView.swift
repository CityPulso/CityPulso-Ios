import PulsoLinkCore
import SwiftUI

/**
 * 主题页（对应 Android `PulsoAppearanceSettings`）：外观模式、强调色、灰色调、平台风格（圆角档位）、面板背景，
 * 下面是按草稿实时渲染的预览卡；改动先进草稿，「保存」才交给调用方保存并同步，「取消」退回。
 * 字体和缩放在 iOS 跟随系统（动态字体），这里不编辑，原值保留。
 */
public struct PulsoThemeSettingsView: View {
    private let settings: PulsoThemeSettings
    private let onSave: (PulsoThemeSettings) -> Void

    @State private var draft: PulsoThemeSettings
    @Environment(\.pulsoPalette) private var palette

    public init(settings: PulsoThemeSettings, onSave: @escaping (PulsoThemeSettings) -> Void) {
        self.settings = settings
        self.onSave = onSave
        _draft = State(initialValue: settings)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s5) {
                Text("pulso_ui_theme_desc", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)

                section("pulso_ui_appearance_label", "circle.lefthalf.filled") {
                    PulsoSegmentedControl([ThemeAppearance.light, .dark, .system], selection: $draft.appearance) { appearance in
                        switch appearance {
                        case .light: Text("pulso_ui_appearance_light", bundle: .module)
                        case .dark: Text("pulso_ui_appearance_dark", bundle: .module)
                        case .system: Text("pulso_ui_appearance_system", bundle: .module)
                        }
                    }
                }

                section("pulso_ui_accent_label", "paintpalette") {
                    PulsoFlowLayout(spacing: PulsoSpace.s2) {
                        ForEach(ThemeAccentColor.allCases, id: \.self) { accent in
                            PulsoSwatch(color: RadixScale(accent).step(9), selected: accent == draft.accent, label: accent.rawValue) {
                                draft.accent = accent
                            }
                        }
                    }
                }

                section("pulso_ui_gray_label", "circle.righthalf.filled") {
                    PulsoFlowLayout(spacing: PulsoSpace.s2) {
                        ForEach(ThemeGrayColor.allCases, id: \.self) { gray in
                            PulsoSwatch(color: RadixScale(gray.resolved(for: draft.accent)).step(9), selected: gray == draft.gray, label: gray.rawValue) {
                                draft.gray = gray
                            }
                        }
                    }
                }

                section("pulso_ui_platform_label", "iphone") {
                    PulsoSegmentedControl(ThemeRadius.allCases, selection: $draft.radius) { radius in
                        switch radius {
                        case .none: Text(verbatim: "Linux")
                        case .small: Text(verbatim: "Android")
                        case .medium: Text("pulso_ui_platform_other", bundle: .module)
                        case .large: Text(verbatim: "Windows")
                        case .full: Text(verbatim: "iOS")
                        }
                    }
                }

                section("pulso_ui_panel_label", "square.stack.3d.up") {
                    PulsoSegmentedControl(ThemePanelBackground.allCases, selection: $draft.panelBackground) { panel in
                        switch panel {
                        case .solid: Text("pulso_ui_panel_solid", bundle: .module)
                        case .translucent: Text("pulso_ui_panel_translucent", bundle: .module)
                        }
                    }
                }

                section("pulso_ui_preview_label", "eye") {
                    ThemePreviewCard()
                        .environment(\.pulsoPalette, PulsoPalette(draft))
                }

                HStack(spacing: PulsoSpace.s2) {
                    Spacer()
                    Button {
                        draft = settings
                    } label: {
                        Label { Text("pulso_ui_cancel", bundle: .module) } icon: { Image(systemName: "arrow.counterclockwise") }
                    }
                    .buttonStyle(.pulso(.soft, tone: .gray))
                    Button {
                        onSave(draft)
                    } label: {
                        Label { Text("pulso_ui_save", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                    }
                    .buttonStyle(.pulso())
                }
                .disabled(draft == settings)
            }
            .padding([.horizontal, .bottom], PulsoSpace.s4)
        }
        .navigationTitle(Text("pulso_ui_theme_title", bundle: .module))
        .onChange(of: settings) { _, saved in draft = saved }
    }

    /** 小节：24pt 图标 + 半粗标题，下面是控件（Android `SettingSection`）。 */
    private func section(_ title: LocalizedStringKey, _ systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s2) {
            HStack(spacing: PulsoSpace.s2) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 24, height: 24)
                Text(title, bundle: .module)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
            }
            content()
        }
    }
}

/** 颜色选块（Android `PulsoSwatch`）：28pt，chip 圆角；选中打勾 + 正文色描边。 */
struct PulsoSwatch: View {
    let color: Color
    let selected: Bool
    let label: String
    let action: () -> Void

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        Button(action: action) {
            palette.chipShape
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    if selected {
                        palette.chipShape.stroke(palette.text, lineWidth: pulsoStrokeEmphasis)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/** 预览卡（Android `ThemePreviewCard`）：强调色斜向渐变底上浮一张面板，放三种按钮、输入框、开关和三语样张。 */
private struct ThemePreviewCard: View {
    @Environment(\.pulsoPalette) private var palette
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s2) {
            Text("pulso_ui_preview_heading", bundle: .module)
                .font(.headline)
                .foregroundStyle(palette.text)
            HStack(spacing: PulsoSpace.s2) {
                Button {} label: { Text("pulso_ui_preview_solid", bundle: .module) }
                    .buttonStyle(.pulso())
                Button {} label: { Text("pulso_ui_preview_soft", bundle: .module) }
                    .buttonStyle(.pulso(.soft))
                Button {} label: { Text("pulso_ui_preview_outline", bundle: .module) }
                    .buttonStyle(.pulso(.outline))
            }
            PulsoTextField(label: Text("pulso_ui_preview_input", bundle: .module), text: $input)
            Toggle(isOn: .constant(true)) {
                Text("pulso_ui_preview_switch", bundle: .module).font(.subheadline).foregroundStyle(palette.text)
            }
            .tint(palette.accent.step(9))
            .fixedSize()
            Group {
                Text(verbatim: "The quick brown fox jumps over the lazy dog.")
                Text(verbatim: "敏捷的棕色狐狸跳过懒惰的狗。")
                Text(verbatim: "Le vif renard brun saute par-dessus le chien paresseux.")
            }
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText)
        }
        .padding(PulsoSpace.s4)
        .background(palette.panel, in: palette.cardShape)
        .overlay { palette.cardShape.strokeBorder(palette.outlineVariant, lineWidth: pulsoHairline) }
        .padding(PulsoSpace.s4)
        .background {
            LinearGradient(
                colors: [palette.accent.step(9).opacity(0.6), .clear, palette.accent.step(7).opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(palette.background)
        }
        .clipShape(palette.cardShape)
    }
}
