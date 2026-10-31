import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 点了通知打开哪一页（Android `NotificationTarget`，WEB `notificationLink`）。 */
enum NotificationTarget: Hashable {
    case event(LoopSport, String)
    case courtBooking(VenueSport, String)
    case membershipPurchase(String)
    case membership(String)
    case bundle(String)
    case tournament(String)
    case myTournaments
    case socialProfile(String)
    case identities
    /** 我标记的地点审完了。 */
    case placeRequests
    case post(String)
    case forum(String)
    case forumManage(String)

    var route: LoopRoute {
        switch self {
        case let .event(sport, id): .event(sport: sport, eventId: id)
        case let .courtBooking(sport, id): .courtBooking(sport: sport, bookingId: id)
        case let .membershipPurchase(id): .myMembershipPurchase(purchaseId: id)
        case let .membership(id): .myMembership(membershipId: id)
        case let .bundle(id): .myBundle(bundleId: id)
        case let .tournament(id): .tournament(tournamentId: id)
        case .myTournaments: .myTournaments
        case let .socialProfile(id): .socialProfile(profileId: id)
        case .identities: .identities
        case .placeRequests: .placeRequests
        case let .post(id): .post(postId: id)
        case let .forum(id): .forum(forumId: id)
        case let .forumManage(id): .forumManage(forumId: id)
        }
    }
}

/** 收件箱的一行（Android `NotificationRowUi`）。 */
struct NotificationRowUi: Identifiable {
    let id: String
    let titleKey: String
    /** 载荷里的文字；nil 时显示通用的一句。 */
    let bodyText: String?
    let receivedAt: String
    let isRead: Bool
    /** wire 类型（`loop.booking.confirmed`、`link.social.profile_followed` …）；没有发起人时按它选图标。 */
    let type: String
    let actorName: String?
    let actorAvatarURL: URL?
    let target: NotificationTarget?
}

/** 收件箱（Android `NotificationsViewModel`），离线优先：行来自本地库，推送和重连会刷新。 */
@MainActor
@Observable
final class NotificationsModel {
    var filter = NotificationInboxFilter.all {
        didSet { if filter != oldValue { list = communicationService.notifications(owner, unreadOnly: filter == .unread) } }
    }

    private(set) var list: MediatedList<NotificationInboxItem>
    private(set) var unreadCount = 0
    private(set) var isMarkingAllRead = false

    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let owner: String

    init() {
        owner = Container.shared.authSessionStore().state.value.currentProfileId
        list = Container.shared.communicationService().notifications(owner, unreadOnly: false)
    }

    var rows: [NotificationRowUi] { list.items.map(row) }

    func observeUnread() async {
        for await count in communicationService.observeUnreadNotificationCount(owner) {
            unreadCount = count
        }
    }

    func markRead(_ row: NotificationRowUi) async {
        guard !row.isRead else { return }
        do {
            try await communicationService.markNotificationRead(owner, row.id)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_notifications_mark_read_failed")
        }
    }

    func markAllRead() async {
        guard !isMarkingAllRead else { return }
        isMarkingAllRead = true
        defer { isMarkingAllRead = false }
        do {
            try await communicationService.markAllNotificationsRead(owner)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_notifications_mark_all_read_failed")
        }
    }

    private func row(_ item: NotificationInboxItem) -> NotificationRowUi {
        NotificationRowUi(
            id: item.id,
            titleKey: Self.titles[item.notificationType] ?? "shell_notifications_fallback",
            bodyText: body(item),
            receivedAt: DateTimeFormatters.monthDayTime(item.receivedAt) ?? item.receivedAt,
            isRead: item.readAt != nil,
            type: item.notificationType,
            actorName: item.actor?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            actorAvatarURL: ImageURLs.image(item.actor?.avatarImageId, base: config.apiBaseURL),
            target: target(item)
        )
    }

    /** 按资源类型选页面；发给组织身份的通知打开球馆后台（在 WEB 上）。不认识的类型返回 nil。 */
    private func target(_ item: NotificationInboxItem) -> NotificationTarget? {
        if item.source == "link" { return linkTarget(item) }
        if !item.source.isEmpty, item.source != "loop" { return nil }
        let id = item.resourceId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        let staff = item.recipientProfileScope == "organization"
        switch item.resourceType {
        case "badminton_court_booking": return staff ? nil : .courtBooking(.badminton, id)
        case "tennis_court_booking": return staff ? nil : .courtBooking(.tennis, id)
        case "pickleball_court_booking": return staff ? nil : .courtBooking(.pickleball, id)
        case "membership": return staff ? nil : .membership(id)
        case "membership_purchase": return staff ? nil : .membershipPurchase(id)
        case "bundle": return staff ? nil : .bundle(id)
        case "tournament": return tournamentTarget(id, item.notificationType, staff)
        case "forum_post": return .post(id)
        case "forum": return item.notificationType == "loop.discussion.join_requested" ? .forumManage(id) : .forum(id)
        default:
            // `<sport>_event`：11 种运动的活动。
            guard item.resourceType.hasSuffix("_event") else { return nil }
            let sport = LoopSport.fromWire(String(item.resourceType.dropLast("_event".count)))
            return .event(sport, id)
        }
    }

    /** 申请结果打开身份；新粉丝 / 新好友打开对方的社区主页。审核队列在 WEB 上。 */
    private func linkTarget(_ item: NotificationInboxItem) -> NotificationTarget? {
        let kind = item.notificationType.split(separator: ".").last.map(String.init) ?? ""
        if kind.hasSuffix("_application_approved") || kind.hasSuffix("_application_rejected") { return .identities }
        if kind.hasPrefix("place_request_") { return .placeRequests }
        guard let actor = item.actor else { return nil }
        return actor.profileScope == "community" && item.notificationType.hasPrefix("link.social.") ? .socialProfile(actor.profileId) : nil
    }

    /** 球馆后台的通知在 WEB；球员的打开「我的赛事」；其余打开赛事页。 */
    private func tournamentTarget(_ id: String, _ type: String, _ staff: Bool) -> NotificationTarget? {
        let kind = type.hasPrefix("loop.tournament.") ? String(type.dropFirst("loop.tournament.".count)) : type
        if staff || kind.hasPrefix("venue_") || kind.hasPrefix("allocation_") { return nil }
        if kind.hasPrefix("entry_") || kind == "prize_granted" { return .myTournaments }
        return .tournament(id)
    }

    private func body(_ item: NotificationInboxItem) -> String? {
        item.payload.text("title")
            ?? item.actor?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? item.payload.text("actor_display_name")
            ?? item.payload.text("venue_name")
            ?? item.payload.text("building_name")
            ?? item.payload.text("reason")
    }

    /** Loop 和 Link 的通知（社交、角色申请、积分、建筑）在同一个收件箱。 */
    private static let titles: [String: String] = [
        "loop.booking.requested": "shell_notifications_type_court_booking_requested",
        "loop.booking.confirmed": "shell_notifications_type_court_booking_confirmed",
        "loop.booking.canceled": "shell_notifications_type_court_booking_canceled",
        "loop.booking.expired": "shell_notifications_type_court_booking_expired",
        "loop.booking.refunded": "shell_notifications_type_court_booking_refunded",
        "loop.booking.paid_at_venue": "shell_notifications_type_court_booking_paid_at_venue",
        "loop.membership.requested": "shell_notifications_type_membership_purchase_requested",
        "loop.membership.confirmed": "shell_notifications_type_membership_purchase_confirmed",
        "loop.membership.canceled": "shell_notifications_type_membership_purchase_canceled",
        "loop.bundle.requested": "shell_notifications_type_bundle_purchase_requested",
        "loop.bundle.confirmed": "shell_notifications_type_bundle_purchase_confirmed",
        "loop.bundle.canceled": "shell_notifications_type_bundle_purchase_canceled",
        "loop.registration.paid": "shell_notifications_type_registration_paid",
        "loop.registration.refunded": "shell_notifications_type_registration_refunded",
        "loop.venue.member_added": "shell_notifications_type_venue_member_added",
        "loop.tournament.host_invited": "shell_notifications_type_tournament_host_invited",
        "loop.tournament.host_answered": "shell_notifications_type_tournament_host_answered",
        "loop.tournament.host_removed": "shell_notifications_type_tournament_host_removed",
        "loop.tournament.venue_invited": "shell_notifications_type_tournament_venue_invited",
        "loop.tournament.venue_answered": "shell_notifications_type_tournament_venue_answered",
        "loop.tournament.venue_withdrew": "shell_notifications_type_tournament_venue_withdrew",
        "loop.tournament.allocation_requested": "shell_notifications_type_tournament_allocation_requested",
        "loop.tournament.allocation_answered": "shell_notifications_type_tournament_allocation_answered",
        "loop.tournament.allocation_released": "shell_notifications_type_tournament_allocation_released",
        "loop.tournament.published": "shell_notifications_type_tournament_published",
        "loop.tournament.canceled": "shell_notifications_type_tournament_canceled",
        "loop.tournament.entry_invited": "shell_notifications_type_tournament_entry_invited",
        "loop.tournament.entry_answered": "shell_notifications_type_tournament_entry_answered",
        "loop.tournament.entry_requested": "shell_notifications_type_tournament_entry_requested",
        "loop.tournament.entry_confirmed": "shell_notifications_type_tournament_entry_confirmed",
        "loop.tournament.entry_canceled": "shell_notifications_type_tournament_entry_canceled",
        "loop.tournament.entry_promoted": "shell_notifications_type_tournament_entry_promoted",
        "loop.tournament.prize_change_requested": "shell_notifications_type_tournament_prize_change_requested",
        "loop.tournament.prize_change_answered": "shell_notifications_type_tournament_prize_change_answered",
        "loop.tournament.results_confirmed": "shell_notifications_type_tournament_results_confirmed",
        "loop.tournament.prize_granted": "shell_notifications_type_tournament_prize_granted",
        "loop.discussion.post_commented": "shell_notifications_type_discussion_post_commented",
        "loop.discussion.comment_replied": "shell_notifications_type_discussion_comment_replied",
        "loop.discussion.post_approved": "shell_notifications_type_discussion_post_approved",
        "loop.discussion.post_rejected": "shell_notifications_type_discussion_post_rejected",
        "loop.discussion.join_requested": "shell_notifications_type_discussion_join_requested",
        "loop.discussion.join_approved": "shell_notifications_type_discussion_join_approved",
        "loop.discussion.join_rejected": "shell_notifications_type_discussion_join_rejected",
        "link.auth.authority_application_approved": "shell_notifications_type_link_auth_authority_application_approved",
        "link.auth.authority_application_rejected": "shell_notifications_type_link_auth_authority_application_rejected",
        "link.auth.authority_application_submitted": "shell_notifications_type_link_auth_authority_application_submitted",
        "link.auth.coach_application_approved": "shell_notifications_type_link_auth_coach_application_approved",
        "link.auth.coach_application_rejected": "shell_notifications_type_link_auth_coach_application_rejected",
        "link.auth.coach_application_submitted": "shell_notifications_type_link_auth_coach_application_submitted",
        "link.auth.creator_application_approved": "shell_notifications_type_link_auth_creator_application_approved",
        "link.auth.creator_application_rejected": "shell_notifications_type_link_auth_creator_application_rejected",
        "link.auth.creator_application_submitted": "shell_notifications_type_link_auth_creator_application_submitted",
        "link.auth.organization_application_approved": "shell_notifications_type_link_auth_organization_application_approved",
        "link.auth.organization_application_rejected": "shell_notifications_type_link_auth_organization_application_rejected",
        "link.auth.organization_application_submitted": "shell_notifications_type_link_auth_organization_application_submitted",
        "link.payments.credit_purchase_succeeded": "shell_notifications_type_link_payments_credit_purchase_succeeded",
        "link.resource.building_link_revoked": "shell_notifications_type_link_resource_building_link_revoked",
        "link.resource.building_request_approved": "shell_notifications_type_link_resource_building_request_approved",
        "link.resource.building_request_cancelled": "shell_notifications_type_link_resource_building_request_cancelled",
        "link.resource.building_request_rejected": "shell_notifications_type_link_resource_building_request_rejected",
        "link.resource.building_request_submitted": "shell_notifications_type_link_resource_building_request_submitted",
        "link.resource.place_request_approved": "shell_notifications_type_link_resource_place_request_approved",
        "link.resource.place_request_rejected": "shell_notifications_type_link_resource_place_request_rejected",
        "link.social.friendship_accepted": "shell_notifications_type_link_social_friendship_accepted",
        "link.social.profile_followed": "shell_notifications_type_link_social_profile_followed",
    ]
}

/** 通知（Android `NotificationsScreen`）：全部 / 未读（带数字），全部已读；点一条标成已读并打开对应页面。 */
struct NotificationsView: View {
    @State private var model = NotificationsModel()
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        let list = model.list
        let rows = model.rows
        VStack(spacing: 0) {
            // 全部 / 未读（带数字），「全部已读」固定在这一行末尾（Android PulsoHighlightTabRow trailing）。
            PulsoHighlightTabRow([NotificationInboxFilter.all, .unread], selection: $model.filter) { filter in
                if filter == .all {
                    Text("shell_notifications_filter_all")
                } else if model.unreadCount > 0 {
                    Text(verbatim: localizedFormat("shell_notifications_filter_unread_count", model.unreadCount))
                } else {
                    Text("shell_notifications_filter_unread")
                }
            } trailing: {
                Button("shell_notifications_mark_all_read") { Task { await model.markAllRead() } }
                    .buttonStyle(.pulso(.ghost, size: .small))
                    .disabled(model.unreadCount == 0 || model.isMarkingAllRead)
            }
            .padding(.vertical, PulsoSpace.s1)
            List {
                if !rows.isEmpty {
                    if let stale = list.staleError { PulsoErrorBanner(stale) { Task { await list.refresh() } } }
                    ForEach(rows) { row in
                        Button {
                            Task { await model.markRead(row) }
                            if let target = row.target { shell?.push(target.route) }
                        } label: {
                            notificationRow(row)
                        }
                        .buttonStyle(.plain)
                        .onAppear { if row.id == rows.last?.id { list.loadMore() } }
                    }
                    if list.isLoadingMore { ProgressView().frame(maxWidth: .infinity) }
                } else if list.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
                } else if let error = list.error {
                    PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
                } else {
                    PulsoEmptyState(Text("shell_notifications_empty"), description: Text("shell_notifications_empty_hint"))
                        .frame(minHeight: 420)
                        .listRowBackground(Color.clear)
                }
            }
            .refreshable { await list.refresh() }
        }
        .navigationTitle("shell_dest_notifications")
        .task(id: model.filter) { await model.list.observe() }
        .task { await model.observeUnread() }
    }

    private func notificationRow(_ row: NotificationRowUi) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if row.actorName != nil || row.actorAvatarURL != nil {
                PulsoAvatar(url: row.actorAvatarURL, size: 40, fallbackText: row.actorName)
            } else {
                Image(systemName: Self.symbol(row.type))
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(row.titleKey)).font(.subheadline.weight(row.isRead ? .regular : .semibold))
                Text(verbatim: row.bodyText ?? String(localized: "shell_notifications_fallback")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(verbatim: row.receivedAt).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !row.isRead { Circle().fill(.tint).frame(width: 8, height: 8).padding(.top, 6) }
        }
        .contentShape(.rect)
    }

    /** 没有发起人时按类型选图标（Android `notificationIcon`）。 */
    private static func symbol(_ type: String) -> String {
        if type.contains(".booking.") { return "calendar.badge.checkmark" }
        if type.contains(".membership.") { return "person.text.rectangle" }
        if type.contains(".bundle.") { return "timer" }
        if type.contains(".registration.") { return "ticket" }
        if type.contains(".tournament.") { return "trophy" }
        if type.contains(".discussion.") { return "text.bubble" }
        if type.contains(".venue.") { return "storefront" }
        if type.hasPrefix("link.auth.") { return "person.text.rectangle" }
        if type.hasPrefix("link.payments.") { return "creditcard" }
        if type.hasPrefix("link.resource.") { return "building.2" }
        if type.hasPrefix("link.social.") { return "person.2" }
        return "bell"
    }
}
