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
    /** 切底栏页面时新页从点按位置圆形扩散铺满（YouNeary 开，YouLoopy 不开）。 */
    private let circularReveal: Bool

    @State private var tapOrigin: CGPoint?
    @State private var revealing: ShellDestination?
    @State private var previous: ShellDestination?
    @State private var revealProgress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        preference: ResolvedAndroidPreference,
        trayDestinations: [ShellDestination],
        navigator: PulsoShellNavigator,
        circularReveal: Bool = false,
        @ViewBuilder page: @escaping (ShellDestination) -> Page
    ) {
        self.preference = preference
        self.trayDestinations = trayDestinations
        self.navigator = navigator
        self.circularReveal = circularReveal
        self.page = page
    }

    public var body: some View {
        ZStack {
            ForEach(navigator.openedRoots, id: \.self) { destination in
                let visible = destination == navigator.selection
                // During a reveal the old page stays visible underneath the growing circle.
                let underneath = revealing != nil && destination == previous
                NavigationStack(path: navigator.path(for: destination)) {
                    page(destination)
                }
                // 页面用它跳到别的栈底页面（Android navigator.openExplore / openCreate 等）。
                .environment(navigator)
                .mask {
                    if destination == revealing {
                        GeometryReader { proxy in
                            let frame = proxy.frame(in: .global)
                            let origin = tapOrigin.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) } ?? CGPoint(x: frame.width / 2, y: frame.height)
                            let radius = hypot(max(origin.x, frame.width - origin.x), max(origin.y, frame.height - origin.y)) * revealProgress
                            Circle().frame(width: radius * 2, height: radius * 2).position(origin)
                        }
                        .ignoresSafeArea()
                    } else {
                        Rectangle().ignoresSafeArea()
                    }
                }
                .zIndex(destination == revealing ? 1 : 0)
                .opacity(visible || underneath ? 1 : 0)
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
                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tapOrigin = $0.location }, isEnabled: circularReveal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: navigator.selection) { old, new in
            guard circularReveal, !reduceMotion, old != new else { return }
            previous = old
            revealing = new
            revealProgress = 0
            withAnimation(.easeInOut(duration: 0.45)) { revealProgress = 1 } completion: {
                revealing = nil
                previous = nil
            }
        }
        .animation(.smooth, value: navigator.isOnRoot)
        .animation(.smooth, value: navigator.appsExpanded)
    }
}
