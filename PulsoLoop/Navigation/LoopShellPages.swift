import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 底栏目标 → 页面（对应 Android `ShellDestination.route()`）。还没移植的页面先显示「这一页还没做好」。 */
@MainActor
enum LoopShellPages {
    static func page(for destination: ShellDestination) -> some View {
        root(for: destination).loopRoutes()
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
            CalendarView()
        case .create:
            CreateEventView()
        case .explore:
            ExploreView()
        case .courtBookings:
            CourtBookingsView()
        default:
            PulsoComingSoonView(destination)
        }
    }
}
