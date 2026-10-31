import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import XCTest
@testable import PulsoLoop

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
        try await signIn()
        let session = PulsoSessionModel()
        try await capture(NavigationStack { SettingsView() }.environment(session), name: "loop-settings")
        try await capture(NavigationStack { ThemeSettingsView() }, name: "loop-settings-theme")
        try await capture(NavigationStack { NavEditView() }, name: "loop-settings-navedit")
        try await capture(NavigationStack { EventPreferencesView() }, name: "loop-settings-event")
        try await capture(NavigationStack { PermissionsView() }, name: "loop-settings-permissions")
        try await capture(NavigationStack { LauncherIconView() }, name: "loop-settings-appicon")
    }

    func testProfile() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        try await capture(NavigationStack { ProfileOverviewView().loopRoutes() }.environment(session), name: "loop-profile")
        try await capture(NavigationStack { ProfileEditView() }, name: "loop-profile-edit")
        try await capture(NavigationStack { ProfileBackgroundsView() }, name: "loop-profile-backgrounds")
        try await capture(NavigationStack { ProfileIdentitiesView() }, name: "loop-identities")
    }

    /** 每个底栏页面。 */
    func testShellPages() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        for destination in ShellDestination.allCases where Container.shared.pulsoCoreConfig().shellDestinations.contains(destination) {
            try await capture(NavigationStack { LoopShellPages.page(for: destination) }.environment(session), name: "loop-tab-\(destination.rawValue.lowercased())")
        }
    }

    /** 不需要 id 的二级页面。 */
    func testRoutes() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        let routes: [(String, LoopRoute)] = [
            ("theme", LoopRoute.theme),
            ("appIcon", LoopRoute.appIcon),
            ("navEdit", LoopRoute.navEdit),
            ("eventPreferences", LoopRoute.eventPreferences),
            ("storage", LoopRoute.storage),
            ("privacy", LoopRoute.privacy),
            ("permissions", LoopRoute.permissions),
            ("accountSecurity", LoopRoute.accountSecurity),
            ("emails", LoopRoute.emails),
            ("changePassword", LoopRoute.changePassword),
            ("profileEdit", LoopRoute.profileEdit),
            ("backgrounds", LoopRoute.backgrounds),
            ("identities", LoopRoute.identities),
            ("tournaments", LoopRoute.tournaments),
            ("myTournaments", LoopRoute.myTournaments),
            ("friendRequests", LoopRoute.friendRequests),
            ("addFriend", LoopRoute.addFriend),
            ("blocked", LoopRoute.blocked),
            ("forumSearch", LoopRoute.forumSearch),
            ("forumCreate", LoopRoute.forumCreate),
            ("myForums", LoopRoute.myForums),
            ("likedPosts", LoopRoute.likedPosts),
            ("notifications", LoopRoute.notifications),
            ("placeRequests", LoopRoute.placeRequests),
            ("myCourses", LoopRoute.myCourses),
            ("coachPanel", LoopRoute.coachPanel),
            ("myCoaching", LoopRoute.myCoaching),
            ("paymentAccounts", LoopRoute.paymentAccounts),
            ("paymentMethods", LoopRoute.paymentMethods),
            ("mapSettings", LoopRoute.mapSettings),
            ("mapStyle", LoopRoute.mapStyle),
            ("locationMarker", LoopRoute.locationMarker),
            ("locationPick", LoopRoute.locationPick),
        ]
        for (name, route) in routes {
            try await capture(NavigationStack { route.page.loopRoutes() }.environment(session), name: "loop-page-\(name)")
        }
    }

    /**
     * 详情页：从截图账号自己的数据里各取第一条（我发起的活动、收藏的球馆、论坛最新帖子和它的论坛、公开赛事），
     * 再打开详情。拿不到就跳过那一页（不写死 id，dev 库重置后照样能截）。
     */
    func testDetails() async throws {
        try await signIn()
        let session = PulsoSessionModel()
        var routes: [(String, LoopRoute)] = []

        let center = ActivityCenterModel()
        let observing = Task { await center.observe() }
        for _ in 0 ..< 40 where center.hostedItems.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        observing.cancel()
        if let event = center.hostedItems.first {
            routes.append(("event", .event(sport: event.sport, eventId: event.id)))
        }

        let venues = Container.shared.favoriteService().pageVenues(VenueFavoritesFilter())
        await venues.refresh()
        if let venue = venues.items.first {
            // 详情页的收藏心形读不到状态就不显示；把这一次读的结果打到日志里，截图里没有心形时能查原因。
            do {
                let favorited = try await Container.shared.favoriteService().isFavorite(.venue, id: venue.venueId)
                print("screenshot favorite check: \(favorited)")
            } catch {
                print("screenshot favorite check failed: \(error)")
            }
            routes.append(("venue", .venue(venueId: venue.venueId)))
            routes.append(("building", .building(buildingId: venue.building.id)))
        }

        let feed = Container.shared.discussionService().pageFeed(tab: .latest, sport: nil, forumId: nil)
        await feed.refresh()
        if let post = feed.items.first {
            routes.append(("post", .post(postId: post.id)))
            if let forum = post.forums.first { routes.append(("forum", .forum(forumId: forum.forumId))) }
        }

        let tournaments = Container.shared.tournamentService().pagePublic(search: nil, sport: nil)
        await tournaments.refresh()
        if let tournament = tournaments.items.first {
            routes.append(("tournament", .tournament(tournamentId: tournament.id)))
        }

        for (name, route) in routes {
            try await capture(NavigationStack { route.page.loopRoutes() }.environment(session), name: "loop-detail-\(name)")
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
