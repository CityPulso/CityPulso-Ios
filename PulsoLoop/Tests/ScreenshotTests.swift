import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import XCTest
@testable import PulsoLoop

/**
 * 页面截图：在模拟器里把页面画进一个窗口存成 PNG，CI 当 artifact 上传，
 * 用来看页面真实长什么样（没有 Mac 时唯一能看到的方式）。
 */
@MainActor
final class ScreenshotTests: XCTestCase {
    func testDefaultTabBar() async throws {
        try await capture(ShellPreview(appsExpanded: false), name: "loop-shell-default")
    }

    func testAppsTrayExpanded() async throws {
        try await capture(ShellPreview(appsExpanded: true), name: "loop-shell-apps")
    }

    func testWelcome() async throws {
        try await capture(LoopAuthStack(), name: "loop-welcome")
        try await capture(LoopAuthStack().environment(\.locale, Locale(identifier: "zh-Hans")), name: "loop-welcome-zh")
        try await capture(LoopAuthStack(), name: "loop-welcome-dark", style: .dark)
    }

    func testLogin() async throws {
        try await capture(NavigationStack { LoginView() }.environment(AuthNavigator()), name: "loop-login")
    }

    func testSignup() async throws {
        try await capture(NavigationStack { SignupView() }.environment(AuthNavigator()), name: "loop-signup")
    }

    func testSettings() async throws {
        let session = PulsoSessionModel()
        try await capture(NavigationStack { SettingsView() }.environment(session), name: "loop-settings")
        try await capture(NavigationStack { ThemeSettingsView() }, name: "loop-settings-theme")
        try await capture(NavigationStack { NavEditView() }, name: "loop-settings-navedit")
        try await capture(NavigationStack { EventPreferencesView() }, name: "loop-settings-event")
        try await capture(NavigationStack { PermissionsView() }, name: "loop-settings-permissions")
        try await capture(NavigationStack { LauncherIconView() }, name: "loop-settings-appicon")
    }

    private func capture(_ view: some View, name: String, style: UIUserInterfaceStyle = .light) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
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
    @State private var navigator: PulsoShellNavigator

    init(appsExpanded: Bool) {
        let navigator = PulsoShellNavigator(root: .explore)
        navigator.appsExpanded = appsExpanded
        _navigator = State(initialValue: navigator)
    }

    var body: some View {
        PulsoShellView(
            preference: .default,
            trayDestinations: ResolvedAndroidPreference.default.appsTrayDestinations(
                kind: .community,
                supported: Set(ShellDestination.allCases)
            ),
            navigator: navigator
        ) { destination in
            List(1...30, id: \.self) { row in
                Text(verbatim: "\(row)")
            }
            .navigationTitle(destination.labelKey)
        }
    }
}
