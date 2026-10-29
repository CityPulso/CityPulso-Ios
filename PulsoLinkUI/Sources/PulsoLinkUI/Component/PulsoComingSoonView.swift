import PulsoLinkCore
import SwiftUI

/** 还没移植的页面（对应 Android `ComingSoonScaffold`）：系统空状态视图。 */
public struct PulsoComingSoonView: View {
    private let destination: ShellDestination

    public init(_ destination: ShellDestination) {
        self.destination = destination
    }

    public var body: some View {
        ContentUnavailableView {
            Label(destination.labelKey, systemImage: destination.defaultIconPack.systemImage)
        } description: {
            Text("coming_soon_subtitle")
        }
        .navigationTitle(destination.labelKey)
    }
}
