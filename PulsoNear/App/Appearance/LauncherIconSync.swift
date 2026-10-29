import PulsoLinkCore
import UIKit

/**
 * 桌面图标套图（对应 Android `LauncherIconSync`）：偏好里的 nearLauncherIcon → 系统备用图标。
 * iOS 换图标不用重开 App，系统会自己弹一次确认。默认图标本身已带深色版本（随系统深浅色）。
 */
@MainActor
enum LauncherIconSync {
    /** Assets.xcassets 里的备用图标（Scripts/android_assets.py 生成）。 */
    static let darkIconName = "AppIcon-Dark"

    static func apply(_ icon: LauncherIcon) async {
        let name: String? = icon == .dark ? darkIconName : nil
        let application = UIApplication.shared
        guard application.supportsAlternateIcons, application.alternateIconName != name else { return }
        try? await application.setAlternateIconName(name)
    }
}
