import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 底栏目标 → 页面（对应 Android `ShellDestination.route()`）。还没移植的页面先显示「这一页还没做好」。 */
@MainActor
enum LoopShellPages {
    @ViewBuilder
    static func page(for destination: ShellDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        default:
            PulsoComingSoonView(destination)
        }
    }
}
