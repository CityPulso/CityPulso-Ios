import PulsoLinkCore
import SwiftUI

/**
 * 主壳（对应 Android `LoopRootChrome` 的两层结构）：每个打开过的栈底页面一个系统 `NavigationStack`，
 * 只显示当前那个；悬浮玻璃底栏放在底部安全区里，页面内容会从它下面滚过去。
 * 推进去的页面隐藏底栏；「应用」展开时点空白处收起。
 */
public struct PulsoShellView<Page: View>: View {
    private let preference: ResolvedAndroidPreference
    private let trayDestinations: [ShellDestination]
    @Bindable private var navigator: PulsoShellNavigator
    private let page: (ShellDestination) -> Page

    public init(
        preference: ResolvedAndroidPreference,
        trayDestinations: [ShellDestination],
        navigator: PulsoShellNavigator,
        @ViewBuilder page: @escaping (ShellDestination) -> Page
    ) {
        self.preference = preference
        self.trayDestinations = trayDestinations
        self.navigator = navigator
        self.page = page
    }

    public var body: some View {
        ZStack {
            ForEach(navigator.openedRoots, id: \.self) { destination in
                let visible = destination == navigator.selection
                NavigationStack(path: navigator.path(for: destination)) {
                    page(destination)
                }
                // 页面用它跳到别的栈底页面（Android navigator.openExplore / openCreate 等）。
                .environment(navigator)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
            }

            if navigator.appsExpanded {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { navigator.appsExpanded = false }
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if navigator.isOnRoot {
                PulsoFloatingShellNavigation(
                    slots: preference.capsuleSlots,
                    action: preference.slot6,
                    trayDestinations: trayDestinations,
                    selection: navigator.selection,
                    appsExpanded: $navigator.appsExpanded,
                    onOpen: { navigator.open($0) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: navigator.isOnRoot)
        .animation(.smooth, value: navigator.appsExpanded)
    }
}
