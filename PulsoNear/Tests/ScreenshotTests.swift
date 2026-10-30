import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import XCTest
@testable import PulsoNear

/**
 * 页面截图：在模拟器里把页面画进一个窗口存成 PNG，CI 当 artifact 上传，
 * 用来看页面真实长什么样（没有 Mac 时唯一能看到的方式）。
 */
@MainActor
final class ScreenshotTests: XCTestCase {
    func testDefaultTabBar() async throws {
        try await capture(ShellPreview(appsExpanded: false), name: "near-shell-default")
    }

    func testAppsTrayExpanded() async throws {
        try await capture(ShellPreview(appsExpanded: true), name: "near-shell-apps")
    }

    func testWelcome() async throws {
        try await capture(NearAuthStack(), name: "near-welcome")
        try await capture(NearAuthStack().environment(\.locale, Locale(identifier: "zh-Hans")), name: "near-welcome-zh")
        try await capture(NearAuthStack(), name: "near-welcome-dark", style: .dark)
    }

    func testLogin() async throws {
        try await capture(NavigationStack { LoginView() }.environment(AuthNavigator()), name: "near-login")
    }

    func testSignup() async throws {
        try await capture(NavigationStack { SignupView() }.environment(AuthNavigator()), name: "near-signup")
    }

    func testSettings() async throws {
        let session = PulsoSessionModel()
        try await capture(NavigationStack { SettingsView() }.environment(session), name: "near-settings")
        try await capture(NavigationStack { ThemeSettingsView() }, name: "near-settings-theme")
        try await capture(NavigationStack { NavEditView() }, name: "near-settings-navedit")
        try await capture(NavigationStack { ActivityPreferencesView() }, name: "near-settings-event")
        try await capture(NavigationStack { PermissionsView() }, name: "near-settings-permissions")
        try await capture(NavigationStack { LauncherIconView() }, name: "near-settings-appicon")
    }

    func testProfile() async throws {
        Container.shared.profileStore().set(.community(try sampleAccount()))
        let session = PulsoSessionModel()
        try await capture(NavigationStack { ProfileOverviewView().nearRoutes() }.environment(session), name: "near-profile")
        try await capture(NavigationStack { ProfileEditView() }, name: "near-profile-edit")
        try await capture(NavigationStack { ProfileBackgroundsView() }, name: "near-profile-backgrounds")
        try await capture(NavigationStack { ProfileIdentitiesView() }, name: "near-identities")
    }

    /** 每个底栏页面（没有后端时显示加载 / 空状态 / 出错，看布局用）。 */
    /** 每个底栏页面（没有后端时显示加载 / 空状态 / 出错，看布局用）。 */
    func testShellPages() async throws {
        Container.shared.profileStore().set(.community(try sampleAccount()))
        let session = PulsoSessionModel()
        for destination in ShellDestination.allCases where Container.shared.pulsoCoreConfig().shellDestinations.contains(destination) {
            try await capture(NavigationStack { NearShellPages.page(for: destination) }.environment(session), name: "near-tab-\(destination.rawValue.lowercased())")
        }
    }

    /** 不需要 id 的二级页面。 */
    func testRoutes() async throws {
        Container.shared.profileStore().set(.community(try sampleAccount()))
        let session = PulsoSessionModel()
        let routes: [(String, NearRoute)] = [
            ("theme", NearRoute.theme),
            ("appIcon", NearRoute.appIcon),
            ("navEdit", NearRoute.navEdit),
            ("activityPreferences", NearRoute.activityPreferences),
            ("privacy", NearRoute.privacy),
            ("permissions", NearRoute.permissions),
            ("accountSecurity", NearRoute.accountSecurity),
            ("emails", NearRoute.emails),
            ("changePassword", NearRoute.changePassword),
            ("profileEdit", NearRoute.profileEdit),
            ("backgrounds", NearRoute.backgrounds),
            ("identities", NearRoute.identities),
            ("storage", NearRoute.storage),
            ("mapSettings", NearRoute.mapSettings),
            ("mapStyle", NearRoute.mapStyle),
            ("locationMarker", NearRoute.locationMarker),
            ("locationPick", NearRoute.locationPick),
            ("wallet", NearRoute.wallet),
            ("placeRequests", NearRoute.placeRequests),
            ("paymentAccounts", NearRoute.paymentAccounts),
            ("paymentMethods", NearRoute.paymentMethods),
            ("forumSearch", NearRoute.forumSearch),
            ("forumCreate", NearRoute.forumCreate),
            ("myForums", NearRoute.myForums),
            ("likedPosts", NearRoute.likedPosts),
            ("friendRequests", NearRoute.friendRequests),
            ("addFriend", NearRoute.addFriend),
            ("blocked", NearRoute.blocked),
            ("notifications", NearRoute.notifications),
        ]
        for (name, route) in routes {
            try await capture(NavigationStack { route.page.nearRoutes() }.environment(session), name: "near-page-\(name)")
        }
    }

    /** 资料页用的示例账号（不连网；背景图地址取不到时显示占位）。 */
    private func sampleAccount() throws -> FullAccountInformationWithCommunityProfile {
        let json = #"""
        {"account":{"id":"acc-1","account_status":"active","signup_platform":"pulsonear",
         "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"},
         "emails":[{"id":"e1","account_id":"acc-1","email":"lin@example.com","is_primary":true,
           "verified_at":"2026-01-01T00:00:00Z","created_at":"","updated_at":""}],
         "community_profile":{"profile_id":"prof-1","account_id":"acc-1","citypulso_id":"lin_boardgame",
          "profile_language":"zh","display_name":"林小羽","first_name":"小羽","last_name":"林",
          "city":"Toronto","country":"Canada","gender":"female","birthday":"1996-05-20T00:00:00Z",
          "website":"citypulso.com","bio":"周五晚上桌游，周末偶尔打麻将。",
          "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z",
          "community_roles":["pulser","creator"],"favorite_activities":["board_game","mahjong"]}}
        """#
        return try WireCoding.decoder.decode(FullAccountInformationWithCommunityProfile.self, from: Data(json.utf8))
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
