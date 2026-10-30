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
    /** 从地图卡片点「报名」进来：加载完还能报名就直接打开报名弹层。 */
    case joinEvent(sport: LoopSport, eventId: String)
    /** 球馆详情（第 8 组）。 */
    case venue(venueId: String)
    /** 在球馆订某个运动的场（第 8 组）。 */
    case venueBook(venueId: String, sport: VenueSport)
    /** 没有球馆的场馆建筑（第 8 组）。 */
    case building(buildingId: String)
    /** 赛事详情（第 12 组）。 */
    case tournament(tournamentId: String)
    /** 别人的主页（第 10 组）。 */
    case socialProfile(profileId: String)
    /** 标记地图上缺的地点，预填长按的位置（第 7 组）。 */
    case markPlace(latitude: Double, longitude: Double)
    /** 一场活动的收款清单。 */
    case checklist(sport: LoopSport, eventId: String)
    /** 一条订场（第 8 组接上订场详情）。 */
    case courtBooking(sport: VenueSport, bookingId: String)
    case paymentMethods
    /** 选附近搜索的中心点。 */
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
        case let .joinEvent(sport, eventId): EventDetailView(sport: sport, eventId: eventId, openJoin: true)
        case .venue: PulsoComingSoonView(title: "explore_sheet_tag_venue", systemImage: "building.2")
        case let .venueBook(_, sport): PulsoComingSoonView(title: sport.loopSport.labelKey, systemImage: "sportscourt")
        case .building: PulsoComingSoonView(title: "explore_sheet_tag_building", systemImage: "building")
        case .tournament: PulsoComingSoonView(title: "explore_layers_tournaments", systemImage: "trophy")
        case .socialProfile: PulsoComingSoonView(title: "event_detail_participants_view_profile", systemImage: "person.crop.circle")
        case .markPlace: PulsoComingSoonView(title: "place_mark_title", systemImage: "mappin.and.ellipse")
        case let .checklist(sport, eventId): ChecklistView(sport: sport, eventId: eventId)
        case let .courtBooking(sport, _): PulsoComingSoonView(title: sport.loopSport.labelKey, systemImage: "sportscourt")
        case .paymentMethods: PaymentMethodsView()
        case .locationPick: LocationPickView()
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
