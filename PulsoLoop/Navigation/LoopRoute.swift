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
    case socialProfile(profileId: String)
    /** 标记地图上缺的地点；从地图长按进来时预填那个位置。 */
    case markPlace(latitude: Double?, longitude: Double?)
    /** 把被拒的地点改了重新提交。 */
    case resubmitPlace(requestId: String)
    /** 我标记的地点。 */
    case placeRequests
    /** 一场活动的收款清单。 */
    case checklist(sport: LoopSport, eventId: String)
    /** 我的一条订场。 */
    case courtBooking(sport: VenueSport, bookingId: String)
    /** 我的订场列表（底栏没有放「我的订场」时从这里进）。 */
    case courtBookings
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
        case let .venueBook(venueId, sport): VenueBookView(venueId: venueId, sport: sport)
        case let .venueConfirm(venueId, sport, date, ranges): VenueConfirmView(venueId: venueId, sport: sport, dateKey: date, ranges: ranges)
        case .building: PulsoComingSoonView(title: "explore_sheet_tag_building", systemImage: "building")
        case .tournament: PulsoComingSoonView(title: "explore_layers_tournaments", systemImage: "trophy")
        case .socialProfile: PulsoComingSoonView(title: "event_detail_participants_view_profile", systemImage: "person.crop.circle")
        case let .markPlace(latitude, longitude): MarkPlaceView(latitude: latitude, longitude: longitude)
        case let .resubmitPlace(requestId): MarkPlaceView(requestId: requestId)
        case .placeRequests: PlaceRequestsView()
        case let .checklist(sport, eventId): ChecklistView(sport: sport, eventId: eventId)
        case let .courtBooking(sport, bookingId): CourtBookingView(sport: sport, bookingId: bookingId)
        case .courtBookings: CourtBookingsView()
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
