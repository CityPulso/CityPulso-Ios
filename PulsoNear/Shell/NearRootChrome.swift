import PulsoLinkUI
import SwiftUI

/** 主界面根 chrome（对应 Android `NearRootChrome`）：悬浮玻璃底栏 + 各栈底页面，页面见 [NearShellPages]。 */
struct NearRootChrome: View {
    @State private var shell = PulsoShellModel()

    var body: some View {
        PulsoShellView(
            preference: shell.preference,
            trayDestinations: shell.trayDestinations,
            navigator: shell.navigator
        ) { destination in
            NearShellPages.page(for: destination)
        }
    }
}
