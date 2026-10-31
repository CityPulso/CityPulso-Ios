import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import XCTest
@testable import PulsoNear

/**
 * 页面截图：在模拟器里把页面画进一个窗口存成 PNG，CI 当 artifact 上传，
 * 用来看页面真实长什么样（没有 Mac 时唯一能看到的方式）。
 *
 * 登录后的页面连 dev 后端（公网域名）拿真数据：账号从环境变量 `SCREENSHOT_EMAIL` / `SCREENSHOT_PASSWORD`
 * 读（CI 里是 GitHub Secrets，经 `TEST_RUNNER_` 前缀传进来），源码里没有账号。
 */
@MainActor
final class ScreenshotTests: XCTestCase {
    private static var signedIn = false

    /** 用截图账号登录一次（会话留在内存里；CI 不签名时 Keychain 写不进去也没关系）。 */
    private func signIn() async throws {
        guard !Self.signedIn else { return }
        let environment = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(environment["SCREENSHOT_EMAIL"], "SCREENSHOT_EMAIL 没有设置")
        let password = try XCTUnwrap(environment["SCREENSHOT_PASSWORD"], "SCREENSHOT_PASSWORD 没有设置")
        try await Container.shared.communitySignIn().loginWithEmail(email: email, password: password)
        // App 里是主界面回到前台时刷新定位；截图直接画页面，这里先拿一次（CI 把模拟器放在温哥华）。
        // 测试宿主拿不到定位授权时，直接放一个温哥华的缓存位置（和 App 用上次定位是同一条路）。
        await Container.shared.deviceLocationBootstrap().refresh()
        if Container.shared.deviceLocationStore().location.value == nil {
            Container.shared.deviceLocationStore().save(
                DeviceLocation(point: PickedLocation(latitude: 49.2827, longitude: -123.1207), label: "Vancouver")
            )
        }
        Self.signedIn = true
    }

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
        try await signIn()
        let session = PulsoSessionModel()
        try await capture(NavigationStack { SettingsView() }.environment(session), name: "near-settings")
        try await capture(NavigationStack { ThemeSettingsView() }, name: "near-settings-theme")
        try await capture(NavigationStack { NavEditView() }, name: "near-settings-navedit")
        try await capture(NavigationStack { ActivityPreferencesView() }, name: "near-settings-event")
        try await capture(NavigationStack { PermissionsView() }, name: "near-settings-permissions")
        try await capture(NavigationStack { LauncherIconView() }, name: "near-settings-appicon")
    }

    func testProfile() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        try await capture(NavigationStack { ProfileOverviewView().nearRoutes() }.environment(session), name: "near-profile")
        try await capture(NavigationStack { ProfileEditView() }, name: "near-profile-edit")
        try await capture(NavigationStack { ProfileBackgroundsView() }, name: "near-profile-backgrounds")
        try await capture(NavigationStack { ProfileIdentitiesView() }, name: "near-identities")
    }

    /** 每个底栏页面。 */
    /** 每个底栏页面。 */
    func testShellPages() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        for destination in ShellDestination.allCases where Container.shared.pulsoCoreConfig().shellDestinations.contains(destination) {
            try await capture(NavigationStack { NearShellPages.page(for: destination) }.environment(session), name: "near-tab-\(destination.rawValue.lowercased())")
        }
    }

    /** 不需要 id 的二级页面。 */
    func testRoutes() async throws {
        try await signIn()
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

    /**
     * 详情页：从截图账号自己的数据里各取第一条（我发起的活动、收藏的门店、论坛最新帖子和它的论坛），再打开详情。
     * 拿不到就跳过那一页（不写死 id，dev 库重置后照样能截）。
     */
    func testDetails() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        var routes: [(String, NearRoute)] = []

        let center = ActivityCenterModel()
        let observing = Task { await center.observe() }
        for _ in 0 ..< 40 where center.hostedItems.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        observing.cancel()
        if let activity = center.hostedItems.first {
            routes.append(("activity", .activity(activityType: activity.activityType, activityId: activity.id)))
        }

        let venues = Container.shared.favoriteService().pageVenues(VenueFavoritesFilter())
        await venues.refresh()
        if let venue = venues.items.first {
            routes.append(("venue", .venue(venueId: venue.venueId)))
            routes.append(("building", .building(buildingId: venue.building.id)))
        }

        let feed = Container.shared.discussionService().pageFeed(tab: .latest, activityType: nil, forumId: nil)
        await feed.refresh()
        if let post = feed.items.first {
            routes.append(("post", .post(postId: post.id)))
            if let forum = post.forums.first { routes.append(("forum", .forum(forumId: forum.forumId))) }
        }

        for (name, route) in routes {
            try await capture(NavigationStack { route.page.nearRoutes() }.environment(session), name: "near-detail-\(name)")
        }
    }

    private func capture(_ view: some View, name: String, style: UIUserInterfaceStyle = .light) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        // 和 App 根视图一样套上账号的主题偏好。
        window.rootViewController = UIHostingController(rootView: view.pulsoTheme(Container.shared.preferenceService().preference.value.theme))
        window.makeKeyAndVisible()
        try await waitUntilLoaded(window)

        let png = UIGraphicsImageRenderer(bounds: window.bounds).pngData { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: "\(name).png"))
        add(XCTAttachment(data: png, uniformTypeIdentifier: "public.png"))
        // 不隐藏旧窗口（下一张盖在上面）：隐藏会触发页面的 onDisappear，编辑资料等页面会在那时自动保存，
        // 截图账号是真账号，截图不能改它的数据。
    }

    /** 等页面数据回来：转圈消失后再等一会儿让图片画上；最多等 15 秒，超时照样截（截图里能看出还在加载）。 */
    private func waitUntilLoaded(_ window: UIWindow) async throws {
        try await Task.sleep(for: .seconds(1.5))
        for _ in 0..<27 where Self.isSpinning(window) {
            try await Task.sleep(for: .milliseconds(500))
        }
        // 列表数据回来后封面、头像还在下载。
        try await Task.sleep(for: .seconds(3))
    }

    private static func isSpinning(_ view: UIView) -> Bool {
        if let indicator = view as? UIActivityIndicatorView, indicator.isAnimating, !indicator.isHidden, indicator.window != nil {
            return true
        }
        return view.subviews.contains { !$0.isHidden && $0.alpha > 0 && isSpinning($0) }
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
