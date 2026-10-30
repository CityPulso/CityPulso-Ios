import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 推进当前栈的二级页面（对应 Android 的 NavKey）。每个栈底页面都挂了 [nearRoutes]，
 * 所以在哪个 Tab 里点，页面就推进哪个 Tab 的导航栈。
 */
enum NearRoute: Hashable {
    case theme
    case appIcon
    case navEdit
    case activityPreferences
    case privacy
    case permissions
    case accountSecurity
    case emails
    case changePassword
    case profileEdit
    case backgrounds
    case identities
    /** 活动详情（所有活动类型共用一页）。 */
    case activity(activityType: NearActivityKind, activityId: String)
    /** 从地图卡片点「报名」进来：加载完还能报名就直接打开报名弹层。 */
    case joinActivity(activityType: NearActivityKind, activityId: String)
    /** 一场活动的收款清单。 */
    case checklist(activityType: NearActivityKind, activityId: String)
    /** 选附近搜索的中心点。 */
    case locationPick
    /** 活动与预约，停在 [tab]。 */
    case calendar(tab: ActivityCenterTab?)
    /** 我的一条门店预约。 */
    case spaceBooking(activityType: VenueActivityType, bookingId: String)
    /** 门店详情（门店那组移植前是占位页）。 */
    case venue(venueId: String)
    /** 收款账户（Stripe Connect）。 */
    case paymentAccounts
    /** 付款方式（保存的卡）。 */
    case paymentMethods
    /** 别人的主页（社交那组移植前是占位页）。 */
    case socialProfile(profileId: String)
    /** 社交：好友 / 关注 / 粉丝，停在 [tab]。 */
    case social(tab: SocialConnectionsTab)
    /** 还没移植的页面：[title] 是文案 key。 */
    case comingSoon(title: String, systemImage: String)

    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .theme: ThemeSettingsView()
        case .appIcon: LauncherIconView()
        case .navEdit: NavEditView()
        case .activityPreferences: ActivityPreferencesView()
        case .privacy: PrivacySettingsView()
        case .permissions: PermissionsView()
        case .accountSecurity: AccountSecurityView()
        case .emails: EmailAddressesView()
        case .changePassword: ChangePasswordView()
        case .profileEdit: ProfileEditView()
        case .backgrounds: ProfileBackgroundsView()
        case .identities: ProfileIdentitiesView()
        case let .activity(activityType, activityId): ActivityDetailView(activityType: activityType, activityId: activityId)
        case let .joinActivity(activityType, activityId): ActivityDetailView(activityType: activityType, activityId: activityId, openJoin: true)
        case let .checklist(activityType, activityId): ChecklistView(activityType: activityType, activityId: activityId)
        case .locationPick: LocationPickView()
        case let .calendar(tab): CalendarView(initialTab: tab)
        case let .spaceBooking(activityType, bookingId): SpaceBookingView(activityType: activityType, bookingId: bookingId)
        case .venue: PulsoComingSoonView(title: "shell_dest_venue_search", systemImage: "building.2")
        case .paymentAccounts: PaymentAccountsView()
        case .paymentMethods: PaymentMethodsView()
        case .social, .socialProfile: PulsoComingSoonView(title: "shell_dest_social", systemImage: "person.2")
        case let .comingSoon(title, systemImage):
            PulsoComingSoonView(title: LocalizedStringKey(title), systemImage: systemImage)
        }
    }
}

extension View {
    /** 让这个栈能推 [NearRoute]。 */
    func nearRoutes() -> some View {
        navigationDestination(for: NearRoute.self) { $0.page }
    }
}
