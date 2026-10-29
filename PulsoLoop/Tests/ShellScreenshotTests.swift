import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import XCTest

/**
 * 主壳底栏截图：在模拟器里把系统 TabView 画进一个窗口存成 PNG，CI 当 artifact 上传，
 * 用来看 Liquid Glass 底栏真实长什么样（没有 Mac 时唯一能看到的方式）。
 */
@MainActor
final class ShellScreenshotTests: XCTestCase {
    func testDefaultTabBar() async throws {
        try await capture(ShellPreview(), name: "loop-shell-default")
    }

    /** 对照：4 个普通 Tab + 1 个 search 角色 Tab（Apple Music 的布局），看系统会不会单独画出圆形按钮。 */
    func testFourTabsPlusDetached() async throws {
        try await capture(FourPlusOnePreview(), name: "loop-shell-four-plus-one")
    }

    private func capture(_ view: some View, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2))

        let png = UIGraphicsImageRenderer(bounds: window.bounds).pngData { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: "\(name).png"))
        add(XCTAttachment(data: png, uniformTypeIdentifier: "public.png"))
        window.isHidden = true
    }
}

/** 默认底栏：槽 1–4 + 应用 + 槽 6（发起）。 */
private struct ShellPreview: View {
    @State private var selection = PulsoShellTab.destination(.explore)

    var body: some View {
        PulsoShellTabView(
            preference: .default,
            trayDestinations: ResolvedAndroidPreference.default.appsTrayDestinations(
                kind: .community,
                supported: Set(ShellDestination.allCases)
            ),
            selection: $selection
        ) { destination in
            PulsoComingSoonView(destination)
        }
    }
}

private struct FourPlusOnePreview: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab("shell_dest_explore", systemImage: "location.magnifyingglass", value: 0) { PulsoComingSoonView(.explore) }
            Tab("shell_dest_venue_search", systemImage: "building.2", value: 1) { PulsoComingSoonView(.venueSearch) }
            Tab("shell_dest_search", systemImage: "tennis.racket", value: 2) { PulsoComingSoonView(.search) }
            Tab("home_nav_apps", systemImage: "square.grid.2x2", value: 3) { PulsoComingSoonView(.forum) }
            Tab("shell_dest_create", systemImage: "plus", value: 4, role: .search) { PulsoComingSoonView(.create) }
        }
    }
}
