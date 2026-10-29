import PulsoLinkCore
import SwiftUI

/** 主壳当前选中的 Tab：底栏槽位上的页面，或「应用」。 */
public enum PulsoShellTab: Hashable, Sendable {
    case destination(ShellDestination)
    case apps
}

/**
 * 主壳底栏（对应 Android `PulsoFloatingShellNavigation`）：系统 `TabView` + iOS 26 Liquid Glass。
 * 左边胶囊是槽 1–4 和「应用」；槽 6 用系统单独的圆形 Tab（`role: .search` 的位置，与 Apple Music 的搜索同款），
 * 本身不做搜索，只是放用户选的那一页。每个 Tab 自带导航栈，系统负责玻璃、选中态和滚动时收起。
 */
public struct PulsoShellTabView<Page: View>: View {
    private let preference: ResolvedAndroidPreference
    private let trayDestinations: [ShellDestination]
    @Binding private var selection: PulsoShellTab
    private let page: (ShellDestination) -> Page

    public init(
        preference: ResolvedAndroidPreference,
        trayDestinations: [ShellDestination],
        selection: Binding<PulsoShellTab>,
        @ViewBuilder page: @escaping (ShellDestination) -> Page
    ) {
        self.preference = preference
        self.trayDestinations = trayDestinations
        _selection = selection
        self.page = page
    }

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(preference.capsuleSlots, id: \.destination) { slot in
                Tab(slot.destination.labelKey, systemImage: slot.iconPack.systemImage, value: .destination(slot.destination)) {
                    NavigationStack { page(slot.destination) }
                }
            }

            Tab("home_nav_apps", systemImage: "square.grid.2x2", value: .apps) {
                NavigationStack {
                    List(trayDestinations, id: \.self) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.labelKey, systemImage: destination.defaultIconPack.systemImage)
                        }
                    }
                    .navigationTitle("home_nav_apps")
                    .navigationDestination(for: ShellDestination.self) { page($0) }
                }
            }

            Tab(
                preference.slot6.destination.labelKey,
                systemImage: preference.slot6.iconPack.systemImage,
                value: .destination(preference.slot6.destination),
                role: .search
            ) {
                NavigationStack { page(preference.slot6.destination) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
