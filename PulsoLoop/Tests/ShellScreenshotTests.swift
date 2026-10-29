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
