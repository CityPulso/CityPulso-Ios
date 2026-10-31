import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 底栏目标 → 页面（对应 Android `ShellDestination.route()`）。本 App 不支持的目标显示「这一页还没做好」。 */
@MainActor
enum NearShellPages {
    static func page(for destination: ShellDestination) -> some View {
        // 底栏页同二级页：窄标题、点阵页面底（Android `PulsoScaffold`）。
        root(for: destination)
            .toolbarTitleDisplayMode(.inline)
            .pulsoPageBackground()
            .nearRoutes()
    }

    @ViewBuilder
    private static func root(for destination: ShellDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .profile:
            ProfileOverviewView()
        case .create:
            CreateActivityView()
        case .calendar:
            CalendarView(initialTab: nil)
        case .search:
            ActivitySearchView()
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
        case .forum:
            ForumFeedView().postLinkCards()
        case .chatHub:
            ChatHubView()
        case .placeRequests:
            PlaceRequestsView()
        default:
            PulsoComingSoonView(destination)
        }
    }
}
