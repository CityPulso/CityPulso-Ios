import PulsoLinkCore
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
    /** 球馆详情；[sheet] 进来后直接打开会员 / 时长包面板。 */
    case venue(venueId: String, sheet: VenueDetailSheet? = nil)
    /** 在球馆订某个运动的场。 */
    case venueBook(venueId: String, sport: VenueSport)
    /** 确认订场：选好的日期和几段场地。 */
    case venueConfirm(venueId: String, sport: VenueSport, date: String, ranges: [VenueConfirmRange])
    /** 没有球馆的场馆建筑（第 8 组）。 */
    case building(buildingId: String)
    /** 赛事详情（第 12 组）。 */
    case tournament(tournamentId: String)
    /** 别人的主页（第 10 组）。 */
    /** 社交：好友 / 关注 / 粉丝，停在 [tab]。 */
    case social(tab: SocialConnectionsTab)
    case socialProfile(profileId: String)
    /** 标记地图上缺的地点；从地图长按进来时预填那个位置。 */
    case markPlace(latitude: Double?, longitude: Double?)
    /** 把被拒的地点改了重新提交。 */
    case resubmitPlace(requestId: String)
    /** 我标记的地点。 */
    case placeRequests
    /** 课程详情（第 12 组）。 */
    case course(courseId: String)
    /** 教练主页（第 12 组）。 */
    case coach(profileId: String)
    /** 教练面板（第 12 组）。 */
    case coachPanel
    /** 我的一张会员卡（第 9 组）。 */
    case myMembership(membershipId: String)
    /** 钱包，打开时停在 [tab]。 */
    case wallet(tab: WalletTab)
    /** 我的一笔会员申请（等球馆确认）。 */
    case myMembershipPurchase(purchaseId: String)
    /** 我的一个时长包。 */
    case myBundle(bundleId: String)
    /** 收款账户（Stripe Connect）。 */
    case paymentAccounts
    /** 一场活动的收款清单。 */
    case checklist(sport: LoopSport, eventId: String)
    /** 我的一条订场。 */
    case courtBooking(sport: VenueSport, bookingId: String)
    /** 我的订场列表（底栏没有放「我的订场」时从这里进）。 */
    /** 活动与订场，停在 [tab]（订场页的「我的订场」）。 */
    case calendar(tab: ActivityCenterTab?)
    case paymentMethods
    /** 地图设置：样式、定位标记。 */
    case mapSettings
    case mapStyle
    case locationMarker
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
        case let .venue(venueId, sheet): VenueDetailView(venueId: venueId, sheet: sheet)
        case let .venueBook(venueId, sport): VenueBookView(venueId: venueId, sport: sport)
        case let .venueConfirm(venueId, sport, date, ranges): VenueConfirmView(venueId: venueId, sport: sport, dateKey: date, ranges: ranges)
        case let .building(buildingId): BuildingDetailView(buildingId: buildingId)
        case .tournament: PulsoComingSoonView(title: "explore_layers_tournaments", systemImage: "trophy")
        case .social: PulsoComingSoonView(title: "shell_dest_social", systemImage: "person.2")
        case .socialProfile: PulsoComingSoonView(title: "event_detail_participants_view_profile", systemImage: "person.crop.circle")
        case let .markPlace(latitude, longitude): MarkPlaceView(latitude: latitude, longitude: longitude)
        case let .resubmitPlace(requestId): MarkPlaceView(requestId: requestId)
        case .placeRequests: PlaceRequestsView()
        case .course: PulsoComingSoonView(title: "venue_programs_courses", systemImage: "book")
        case .coach: PulsoComingSoonView(title: "venue_programs_coaches", systemImage: "figure.strengthtraining.traditional")
        case .coachPanel: PulsoComingSoonView(title: "venue_programs_coach_panel", systemImage: "rectangle.stack")
        case let .myMembership(membershipId): MyMembershipView(membershipId: membershipId)
        case let .wallet(tab): WalletView(tab: tab)
        case let .myMembershipPurchase(purchaseId): MyMembershipPurchaseView(purchaseId: purchaseId)
        case let .myBundle(bundleId): MyBundleView(bundleId: bundleId)
        case .paymentAccounts: PaymentAccountsView()
        case let .checklist(sport, eventId): ChecklistView(sport: sport, eventId: eventId)
        case let .courtBooking(sport, bookingId): CourtBookingView(sport: sport, bookingId: bookingId)
        case let .calendar(tab): CalendarView(initialTab: tab)
        case .paymentMethods: PaymentMethodsView()
        case .locationPick: LocationPickView()
        case .mapSettings: MapSettingsView()
        case .mapStyle: MapStyleView()
        case .locationMarker: LocationMarkerView()
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
