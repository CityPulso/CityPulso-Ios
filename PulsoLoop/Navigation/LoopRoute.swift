import PulsoLinkUI
import SwiftUI

/**
 * 推进当前栈的二级页面（对应 Android 的 NavKey）。每个栈底页面都挂了 [loopRoutes]，
 * 所以在哪个 Tab 里点，页面就推进哪个 Tab 的导航栈。
 */
enum LoopRoute: Hashable {
    case theme
    case appIcon
    case navEdit
    case eventPreferences
    case privacy
    case permissions
    case accountSecurity
    case emails
    case changePassword
    case profileEdit
    case backgrounds
    case identities
    /** 活动详情（所有运动共用一页）。 */
    case event(sport: LoopSport, eventId: String)
    /** 一条订场（第 8 组接上订场详情）。 */
    case courtBooking(sport: VenueSport, bookingId: String)
    case paymentMethods
    /** 选附近搜索的中心点（第 7 组接上地图选点）。 */
    case locationPick
    /** 还没移植的页面：[title] 是文案 key。 */
    case comingSoon(title: String, systemImage: String)

    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .theme: ThemeSettingsView()
        case .appIcon: LauncherIconView()
        case .navEdit: NavEditView()
        case .eventPreferences: EventPreferencesView()
        case .privacy: PrivacySettingsView()
        case .permissions: PermissionsView()
        case .accountSecurity: AccountSecurityView()
        case .emails: EmailAddressesView()
        case .changePassword: ChangePasswordView()
        case .profileEdit: ProfileEditView()
        case .backgrounds: ProfileBackgroundsView()
        case .identities: ProfileIdentitiesView()
        case let .event(sport, eventId): EventDetailView(sport: sport, eventId: eventId)
        case let .courtBooking(sport, _): PulsoComingSoonView(title: sport.loopSport.labelKey, systemImage: "sportscourt")
        case .paymentMethods: PaymentMethodsView()
        case .locationPick: PulsoComingSoonView(title: "shell_location_pick_title", systemImage: "mappin.and.ellipse")
        case let .comingSoon(title, systemImage):
            PulsoComingSoonView(title: LocalizedStringKey(title), systemImage: systemImage)
        }
    }
}

extension View {
    /** 让这个栈能推 [LoopRoute]。 */
    func loopRoutes() -> some View {
        navigationDestination(for: LoopRoute.self) { $0.page }
    }
}
