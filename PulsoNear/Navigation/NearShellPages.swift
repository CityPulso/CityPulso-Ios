import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 底栏目标 → 页面（对应 Android `ShellDestination.route()`）。还没移植的页面先显示「这一页还没做好」。 */
@MainActor
enum NearShellPages {
    static func page(for destination: ShellDestination) -> some View {
        root(for: destination).nearRoutes()
    }

    @ViewBuilder
    private static func root(for destination: ShellDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        default:
            PulsoComingSoonView(destination)
        }
    }
}
