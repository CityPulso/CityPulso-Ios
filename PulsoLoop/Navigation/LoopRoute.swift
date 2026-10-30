import Factory
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
    /** 清除本地数据。 */
    case storage
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
    /** 赛事页：公开赛事列表，右上角进我的赛事。 */
    case tournaments
    /** 我的赛事（赛事页右上角、报名成功后的「看我的赛事」）。 */
    case myTournaments
    /** 别人的主页（第 10 组）。 */
    /** 社交：好友 / 关注 / 粉丝，停在 [tab]。 */
    case social(tab: SocialConnectionsTab)
    case socialProfile(profileId: String)
    /** 好友请求（收到的 / 发出的）。 */
    case friendRequests
    /** 找人加好友。 */
    case addFriend
    /** 黑名单。 */
    case blocked
    /** 论坛（第 11 组）。 */
    case forum(forumId: String)
    case forumManage(forumId: String)
    case forumSearch
    case forumCreate
    case myForums
    case likedPosts
    case post(postId: String)
    case postCreate(prefill: PostCreatePrefill)
    case postEdit(postId: String)
    /** 通知收件箱（消息页的铃铛）。 */
    case notifications
    /** 聊天室。 */
    case conversation(conversationId: String, isGroup: Bool)
    case chatSettings(conversationId: String, isGroup: Bool)
    case groupMembers(conversationId: String)
    case groupAddMembers(conversationId: String)
    /** 聊天里选位置发出去。 */
    case chatLocationPick(conversationId: String)
    /** 聊天里点开的位置。 */
    case chatLocationView(latitude: Double, longitude: Double, label: String?, address: String?)
    /** 分享我发起的 / 参加的活动。 */
    case chatEventPicker(conversationId: String, hosted: Bool)
    /** 分享收藏（建筑 / 球馆 / 帖子 / 论坛）。 */
    case chatFavoritePicker(conversationId: String)
    /** 标记地图上缺的地点；从地图长按进来时预填那个位置。 */
    case markPlace(latitude: Double?, longitude: Double?)
    /** 把被拒的地点改了重新提交。 */
    case resubmitPlace(requestId: String)
    /** 我标记的地点。 */
    case placeRequests
    /** 课程详情（第 12 组）。 */
    case course(courseId: String)
    /** 我的课程（课程详情报名后的「看我的课程」）。 */
    case myCourses
    /** 教练主页（第 12 组）。 */
    case coach(profileId: String)
    /** 教练面板（第 12 组）。 */
    case coachPanel
    /** 我的私教（课程页右上角进）。 */
    case myCoaching
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
        case .storage: StorageView(service: Container.shared.localDataService())
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
        case let .tournament(tournamentId): TournamentDetailView(tournamentId: tournamentId)
        case .tournaments: TournamentsView()
        case .myTournaments: MyTournamentsView()
        case let .social(tab): SocialOverviewView(initialTab: tab)
        case .friendRequests: FriendRequestsView()
        case .addFriend: AddFriendView()
        case .blocked: BlockedListView()
        case .notifications: NotificationsView()
        case let .post(postId): PostDetailView(postId: postId)
        case let .forum(forumId): ForumDetailView(forumId: forumId).postLinkCards()
        case let .postCreate(prefill): PostCreateView(prefill: prefill)
        case let .postEdit(postId): PostEditView(postId: postId)
        case .forumSearch: ForumSearchView()
        case .myForums: MyForumsView()
        case .likedPosts: LikedPostsView().postLinkCards()
        case let .forumManage(forumId): ForumManageView(forumId: forumId).postLinkCards()
        case .forumCreate: ForumCreateView()
        case let .conversation(conversationId, isGroup): ChatConversationView(conversationId: conversationId, isGroup: isGroup)
        case let .chatSettings(conversationId, isGroup): ChatSettingsView(conversationId: conversationId, isGroup: isGroup)
        case let .groupMembers(conversationId): GroupMembersView(conversationId: conversationId)
        case let .groupAddMembers(conversationId): GroupAddMembersView(conversationId: conversationId)
        case let .chatLocationPick(conversationId): ChatLocationPickView(conversationId: conversationId)
        case let .chatLocationView(latitude, longitude, label, address): ChatLocationView(latitude: latitude, longitude: longitude, label: label, address: address)
        case let .chatEventPicker(conversationId, hosted): ChatEventPickerView(conversationId: conversationId, hosted: hosted)
        case let .chatFavoritePicker(conversationId): ChatFavoritePickerView(conversationId: conversationId)
        case let .socialProfile(profileId): SocialProfileView(profileId: profileId)
        case let .markPlace(latitude, longitude): MarkPlaceView(latitude: latitude, longitude: longitude)
        case let .resubmitPlace(requestId): MarkPlaceView(requestId: requestId)
        case .placeRequests: PlaceRequestsView()
        case let .course(courseId): CourseDetailView(courseId: courseId)
        case .myCourses: MyCoursesView()
        case let .coach(profileId): CoachDetailView(profileId: profileId)
        case .myCoaching: MyCoachingView()
        case .coachPanel: CoachPanelView()
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
