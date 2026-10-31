import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 应用图标（对应 Android `LauncherIconScreen`）：每个图标包一张卡片（选中强调色描边），右下角「保存」才换系统备用图标
 * 并写进偏好同步到账号。iOS 的备用图标立即生效，不需要重开应用，所以不显示 Android 那句「重新打开才生效」。
 */
struct LauncherIconView: View {
    private let saved = Container.shared.preferenceService().preference.value.android.loopLauncherIcon
    @State private var draft = Container.shared.preferenceService().preference.value.android.loopLauncherIcon
    @State private var current: LauncherIcon?
    @State private var saving = false
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: PulsoSpace.s4) {
                ForEach(LauncherIcon.allCases, id: \.self) { icon in
                    Button { draft = icon } label: {
                        PulsoCard(border: icon == draft ? palette.accent.step(9) : nil) {
                            HStack(spacing: PulsoSpace.s4) {
                                Image(icon.previewImage)
                                    .resizable()
                                    .frame(width: 56, height: 56)
                                    .clipShape(.rect(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(icon.titleKey).font(.headline.weight(.regular)).foregroundStyle(palette.text)
                                    Text(icon.descriptionKey).font(.caption).foregroundStyle(palette.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(PulsoSpace.s4)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(icon == draft ? .isSelected : [])
                }
                HStack {
                    Spacer()
                    Button {
                        save()
                    } label: {
                        PulsoButtonLabel("app_icon_save_restart", systemImage: "square.and.arrow.down", loading: saving)
                    }
                    .buttonStyle(.pulso())
                    .disabled(draft == (current ?? saved) || saving)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("app_icon_title")
    }

    private func save() {
        let icon = draft
        saving = true
        Task {
            await LauncherIconSync.apply(icon)
            await PreferenceSync.save { $0.android.loopLauncherIcon = icon }
            current = icon
            saving = false
        }
    }
}

extension LauncherIcon {
    fileprivate var titleKey: LocalizedStringKey {
        switch self {
        case .default: "app_icon_pack_default"
        case .dark: "app_icon_pack_dark"
        }
    }

    fileprivate var descriptionKey: LocalizedStringKey {
        switch self {
        case .default: "app_icon_pack_default_desc"
        case .dark: "app_icon_pack_dark_desc"
        }
    }

    /** Assets.xcassets 里的图标预览图（Scripts/android_assets.py 生成）。 */
    fileprivate var previewImage: String {
        switch self {
        case .default: "app_icon_preview"
        case .dark: "app_icon_preview_dark"
        }
    }
}
