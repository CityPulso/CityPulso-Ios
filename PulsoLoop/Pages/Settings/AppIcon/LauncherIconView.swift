import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 应用图标（对应 Android `LauncherIconScreen`）：选中即换系统备用图标，并写进偏好同步到账号。
 * 默认图标随系统深浅色自动切换；「深色」一直用深色。
 */
struct LauncherIconView: View {
    @State private var selected = Container.shared.preferenceService().preference.value.android.loopLauncherIcon

    var body: some View {
        Form {
            Section {
                ForEach(LauncherIcon.allCases, id: \.self) { icon in
                    Button {
                        select(icon)
                    } label: {
                        HStack(spacing: 16) {
                            Image(icon.previewImage)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(.rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(icon.titleKey)
                                Text(icon.descriptionKey)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if icon == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(icon == selected ? .isSelected : [])
                }
            }
        }
        .navigationTitle("app_icon_title")
    }

    private func select(_ icon: LauncherIcon) {
        guard icon != selected else { return }
        selected = icon
        Task {
            await LauncherIconSync.apply(icon)
            await PreferenceSync.save { $0.android.loopLauncherIcon = icon }
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
