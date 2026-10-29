import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 主界面根 chrome（对应 Android `LoopRootChrome`）：悬浮玻璃底栏 + 各栈底页面，页面见 [LoopShellPages]。 */
struct LoopRootChrome: View {
    @State private var shell = PulsoShellModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PulsoShellView(
            preference: shell.preference,
            trayDestinations: shell.trayDestinations,
            navigator: shell.navigator
        ) { destination in
            LoopShellPages.page(for: destination)
        }
        .task {
            // 桌面图标跟着偏好走（包括从服务端同步下来的）。
            let icons = Container.shared.preferenceService().preference.values().map(\.android.loopLauncherIcon)
            var applied: LauncherIcon?
            for await icon in icons where icon != applied {
                applied = icon
                await LauncherIconSync.apply(icon)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 用户可能刚在系统设置里改了本 App 的语言。
            if phase == .active {
                Task { await AppLanguageSync.sync() }
                // 回到前台重新定位（Android 在 onStart 时同样刷新），附近列表和地图用新位置。
                Task { await Container.shared.deviceLocationBootstrap().refresh() }
            }
        }
    }
}
