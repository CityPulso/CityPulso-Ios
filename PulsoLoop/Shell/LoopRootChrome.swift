import PulsoLinkUI
import SwiftUI

/** 主界面根 chrome（对应 Android `LoopRootChrome`）：系统 TabView 底栏，各槽位的页面见 [LoopShellPages]。 */
struct LoopRootChrome: View {
    @State private var shell = PulsoShellModel()

    var body: some View {
        PulsoShellTabView(
            preference: shell.preference,
            trayDestinations: shell.trayDestinations,
            selection: $shell.selection
        ) { destination in
            LoopShellPages.page(for: destination)
        }
    }
}
