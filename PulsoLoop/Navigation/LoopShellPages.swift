import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 底栏目标 → 页面（对应 Android `ShellDestination.route()`）。本 App 不支持的目标显示「这一页还没做好」。 */
@MainActor
enum LoopShellPages {
    static func page(for destination: ShellDestination) -> some View {
        // 底栏页同二级页：窄标题、点阵页面底（Android `PulsoScaffold`）。
        root(for: destination)
            .toolbarTitleDisplayMode(.inline)
            .pulsoPageBackground()
            .loopRoutes()
    }

    @ViewBuilder
    private static func root(for destination: ShellDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .profile:
            ProfileOverviewView()
        case .search:
            EventSearchView()
        case .calendar:
            CalendarView(isRoot: true)
        case .create:
            CreateEventView()
        case .explore:
            ExploreView()
        case .venueSearch:
            VenueSearchView()
        case .favorites:
            FavoritesView().postLinkCards()
        case .wallet:
            WalletView()
        case .billing:
            BillingView()
        case .courses:
            MyCoursesView()
        case .placeRequests:
            PlaceRequestsView()
        case .tournaments:
            TournamentsView()
        case .chatHub:
            ChatHubView()
        case .forum:
            ForumFeedView().postLinkCards()
        default:
            PulsoComingSoonView(destination)
        }
    }
}
