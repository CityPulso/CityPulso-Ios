import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 点了通知打开哪一页（Android `NotificationTarget`，WEB `notificationLink`）。 */
enum NotificationTarget: Hashable {
    case activity(NearActivityKind, String)
    case spaceBooking(VenueActivityType, String)
    case membershipPurchase(String)
    case membership(String)
    case socialProfile(String)
    case identities
    /** 我标记的地点审完了。 */
    case placeRequests
    case post(String)
    case forum(String)
    case forumManage(String)

    var route: NearRoute {
        switch self {
        case let .activity(activityType, id): .activity(activityType: activityType, activityId: id)
        case let .spaceBooking(activityType, id): .spaceBooking(activityType: activityType, bookingId: id)
        case let .membershipPurchase(id): .myMembershipPurchase(purchaseId: id)
        case let .membership(id): .myMembership(membershipId: id)
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
    /** wire 类型（`near.booking.confirmed`、`link.social.profile_followed` …）；没有发起人时按它选图标。 */
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

    /** 按资源类型选页面；发给组织身份的通知打开门店后台（在 WEB 上）。不认识的类型返回 nil。 */
    private func target(_ item: NotificationInboxItem) -> NotificationTarget? {
        if item.source == "link" { return linkTarget(item) }
        if !item.source.isEmpty, item.source != "near" { return nil }
        let id = item.resourceId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        let staff = item.recipientProfileScope == "organization"
        switch item.resourceType {
        case "membership": return staff ? nil : .membership(id)
        case "membership_purchase": return staff ? nil : .membershipPurchase(id)
        case "forum_post": return .post(id)
        case "forum": return item.notificationType == "near.discussion.join_requested" ? .forumManage(id) : .forum(id)
        default:
            // `<门店类型>_space_booking`：七种门店类型的预约；`<活动类型>_activity`：15 种活动类型的活动。
            if item.resourceType.hasSuffix("_space_booking") {
                guard !staff, let type = VenueActivityType(rawValue: String(item.resourceType.dropLast("_space_booking".count))) else { return nil }
                return .spaceBooking(type, id)
            }
            guard item.resourceType.hasSuffix("_activity"),
                  let kind = NearActivityKind(rawValue: String(item.resourceType.dropLast("_activity".count))) else { return nil }
            return .activity(kind, id)
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

    private func body(_ item: NotificationInboxItem) -> String? {
        item.payload.text("title")
            ?? item.actor?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? item.payload.text("actor_display_name")
            ?? item.payload.text("venue_name")
            ?? item.payload.text("building_name")
            ?? item.payload.text("reason")
    }

    /** Near 和 Link 的通知（社交、角色申请、积分、建筑）在同一个收件箱。 */
    private static let titles: [String: String] = [
        "near.booking.requested": "shell_notifications_type_space_booking_requested",
        "near.booking.confirmed": "shell_notifications_type_space_booking_confirmed",
        "near.booking.canceled": "shell_notifications_type_space_booking_canceled",
        "near.booking.expired": "shell_notifications_type_space_booking_expired",
        "near.booking.refunded": "shell_notifications_type_space_booking_refunded",
        "near.booking.paid_at_venue": "shell_notifications_type_space_booking_paid_at_venue",
        "near.membership.requested": "shell_notifications_type_membership_purchase_requested",
        "near.membership.confirmed": "shell_notifications_type_membership_purchase_confirmed",
        "near.membership.canceled": "shell_notifications_type_membership_purchase_canceled",
        "near.registration.paid": "shell_notifications_type_registration_paid",
        "near.registration.refunded": "shell_notifications_type_registration_refunded",
        "near.venue.member_added": "shell_notifications_type_venue_member_added",
        "near.discussion.post_commented": "shell_notifications_type_discussion_post_commented",
        "near.discussion.comment_replied": "shell_notifications_type_discussion_comment_replied",
        "near.discussion.post_approved": "shell_notifications_type_discussion_post_approved",
        "near.discussion.post_rejected": "shell_notifications_type_discussion_post_rejected",
        "near.discussion.join_requested": "shell_notifications_type_discussion_join_requested",
        "near.discussion.join_approved": "shell_notifications_type_discussion_join_approved",
        "near.discussion.join_rejected": "shell_notifications_type_discussion_join_rejected",
        "link.auth.authority_application_approved": "shell_notifications_type_link_auth_authority_application_approved",
        "link.auth.authority_application_rejected": "shell_notifications_type_link_auth_authority_application_rejected",
        "link.auth.authority_application_submitted": "shell_notifications_type_link_auth_authority_application_submitted",
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
                        .listRowBackground(Color.clear)
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
            // 行直接铺在页面上（Android 通知列表不套卡片）。
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        if type.contains(".registration.") { return "ticket" }
        if type.contains(".discussion.") { return "text.bubble" }
        if type.contains(".venue.") { return "storefront" }
        if type.hasPrefix("link.auth.") { return "person.text.rectangle" }
        if type.hasPrefix("link.payments.") { return "creditcard" }
        if type.hasPrefix("link.resource.") { return "building.2" }
        if type.hasPrefix("link.social.") { return "person.2" }
        return "bell"
    }
}
