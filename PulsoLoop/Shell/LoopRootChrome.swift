import PulsoLinkUI
import SwiftUI

/** 主界面根 chrome（对应 Android `LoopRootChrome`）：悬浮玻璃底栏 + 各栈底页面，页面见 [LoopShellPages]。 */
struct LoopRootChrome: View {
    @State private var shell = PulsoShellModel()

    var body: some View {
        PulsoShellView(
            preference: shell.preference,
            trayDestinations: shell.trayDestinations,
            navigator: shell.navigator
        ) { destination in
            LoopShellPages.page(for: destination)
        }
    }
}
