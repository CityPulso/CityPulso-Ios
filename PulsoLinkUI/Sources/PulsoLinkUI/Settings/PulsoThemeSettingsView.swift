import PulsoLinkCore
import SwiftUI

/**
 * 主题页（对应 Android `PulsoAppearanceSettings`）：iOS 只用外观（浅 / 深 / 跟随系统）和强调色；
 * 其余主题字段（灰阶、圆角、缩放、面板、字体）原样保留给别的端。改动立刻生效，由调用方保存并同步。
 */
public struct PulsoThemeSettingsView: View {
    private let settings: PulsoThemeSettings
    private let onChange: (PulsoThemeSettings) -> Void

    public init(settings: PulsoThemeSettings, onChange: @escaping (PulsoThemeSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    public var body: some View {
        Form {
            Section {
                Picker(selection: binding(\.appearance)) {
                    Text("pulso_ui_appearance_system", bundle: .module).tag(ThemeAppearance.system)
                    Text("pulso_ui_appearance_light", bundle: .module).tag(ThemeAppearance.light)
                    Text("pulso_ui_appearance_dark", bundle: .module).tag(ThemeAppearance.dark)
                } label: {
                    Text("pulso_ui_appearance_label", bundle: .module)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("pulso_ui_appearance_label", bundle: .module)
            } footer: {
                Text("pulso_ui_theme_desc", bundle: .module)
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                    ForEach(ThemeAccentColor.allCases, id: \.self) { accent in
                        Button {
                            var next = settings
                            next.accent = accent
                            onChange(next)
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if accent == settings.accent {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: accent.rawValue.capitalized))
                        .accessibilityAddTraits(accent == settings.accent ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("pulso_ui_accent_label", bundle: .module)
            }
        }
        .navigationTitle(Text("pulso_ui_theme_title", bundle: .module))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PulsoThemeSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var next = settings
                next[keyPath: keyPath] = value
                onChange(next)
            }
        )
    }
}
