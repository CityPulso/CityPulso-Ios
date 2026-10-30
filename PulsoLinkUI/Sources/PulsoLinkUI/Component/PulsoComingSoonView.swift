import PulsoLinkCore
import SwiftUI

/** 还没开放的运动 / 活动类型和本 App 不支持的页面（对应 Android `ComingSoonScaffold`）：系统空状态视图。 */
public struct PulsoComingSoonView: View {
    private let title: LocalizedStringKey
    private let systemImage: String

    public init(_ destination: ShellDestination) {
        title = destination.labelKey
        systemImage = destination.defaultIconPack.systemImage
    }

    /** [title] 是 App 文案 key。 */
    public init(title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("coming_soon_subtitle")
        }
        .navigationTitle(title)
    }
}
