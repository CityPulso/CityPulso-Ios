import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 底栏目标 → 页面（对应 Android `ShellDestination.route()`）。还没移植的页面先显示「这一页还没做好」。 */
@MainActor
enum NearShellPages {
    static func page(for destination: ShellDestination) -> some View {
        root(for: destination).nearRoutes()
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
        default:
            PulsoComingSoonView(destination)
        }
    }
}
