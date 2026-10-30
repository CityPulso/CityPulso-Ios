import PulsoLinkCore
import SwiftUI

/**
 * 主壳导航状态（对应 Android `LoopNavCoordinator` 的栈底部分）：当前栈底页面、每个栈底页面自己的导航路径、
 * 「应用」托盘是否展开。打开过的栈底页面一直保留，切回来时滚动位置和推进去的页面都还在。
 */
@MainActor
@Observable
public final class PulsoShellNavigator {
    public private(set) var selection: ShellDestination
    public private(set) var openedRoots: [ShellDestination]
    public var appsExpanded = false
    private var paths: [ShellDestination: NavigationPath] = [:]

    public init(root: ShellDestination) {
        selection = root
        openedRoots = [root]
    }

    /** 打开一个栈底页面；点的就是当前页面时回到它的第一屏（与系统 Tab 栏一致）。 */
    public func open(_ destination: ShellDestination) {
        appsExpanded = false
        if destination == selection {
            paths[destination] = NavigationPath()
            return
        }
        if !openedRoots.contains(destination) { openedRoots.append(destination) }
        selection = destination
    }

    /** 在当前栈底页面上推一个页面（侧栏、深链等页面外的入口用）。 */
    public func push(_ route: some Hashable) {
        paths[selection, default: NavigationPath()].append(route)
    }

    /** 当前栈退回 [count] 页（比如删了论坛，管理页和论坛页一起退出）。 */
    public func pop(_ count: Int = 1) {
        var path = paths[selection, default: NavigationPath()]
        path.removeLast(min(count, path.count))
        paths[selection] = path
    }

    /** 把当前栈最上面的页面换成 [route]（比如发完帖进帖子详情，返回时不再回到表单）。 */
    public func replaceTop(with route: some Hashable) {
        var path = paths[selection, default: NavigationPath()]
        if !path.isEmpty { path.removeLast() }
        path.append(route)
        paths[selection] = path
    }

    public func path(for destination: ShellDestination) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[destination] ?? NavigationPath() },
            set: { self.paths[destination] = $0 }
        )
    }

    /** 当前页面在第一屏（底栏只在第一屏显示；推进去的页面盖住底栏，与 Android level 3 一致）。 */
    public var isOnRoot: Bool {
        paths[selection]?.isEmpty ?? true
    }
}
