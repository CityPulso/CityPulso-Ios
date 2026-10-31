import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 要按住确认的关系操作（删好友 / 移除粉丝 / 拉黑）。 */
private struct SocialHoldAction: Identifiable {
    enum Kind { case removeFriend, removeFollower, block }

    let kind: Kind
    let row: SocialConnectionRowUi

    var id: String { "\(kind)-\(row.profileId)" }
}

/**
 * 社交（Android `SocialOverviewScreen`）：搜索自己的列表 + 好友 / 关注 / 粉丝三个标签的分页列表；
 * 右上角是消息和「+」（好友请求、找人、黑名单）。
 */
struct SocialOverviewView: View {
    @Environment(\.pulsoPalette) private var palette
    @State private var model: SocialOverviewModel
    @State private var holding: SocialHoldAction?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(initialTab: SocialConnectionsTab = .friends) {
        _model = State(initialValue: SocialOverviewModel(initialTab: initialTab))
    }

    var body: some View {
        VStack(spacing: 0) {
            PulsoUnderlineTabRow(SocialConnectionsTab.allCases, selection: Binding(get: { model.tab }, set: { model.selectTab($0) })) { Text(tabLabel($0)) }
            VStack(spacing: PulsoSpace.s2) {
                PulsoSearchField(text: $model.query, prompt: Text("shell_social_search_placeholder"))
                HStack {
                    Text(verbatim: localizedFormat("shell_social_list_total", String(localized: totalLabel(model.tab)), model.counts[model.tab].map(String.init) ?? "—"))
                        .font(.footnote).foregroundStyle(palette.secondaryText)
                    Spacer()
                    PulsoMenuSelect([SocialRelationSort.newest, .oldest], selection: $model.sort, size: .small) { sort in
                        Text(sort == .newest ? "shell_social_sort_newest" : "shell_social_sort_oldest")
                    }
                }
            }
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
            List {
                content
            }
            .refreshable { await model.refresh() }
        }
        .navigationTitle("shell_dest_social")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shell?.open(.chatHub) } label: { Label("shell_dest_chat_hub", systemImage: "bubble.left.and.bubble.right") }
                Menu {
                    NavigationLink(value: NearRoute.friendRequests) { Label("shell_social_requests", systemImage: "person.badge.plus") }
                    NavigationLink(value: NearRoute.addFriend) { Label("shell_social_find_people", systemImage: "person.crop.circle.badge.magnifyingglass") }
                    NavigationLink(value: NearRoute.blocked) { Label("shell_social_blocked_title", systemImage: "nosign") }
                } label: {
                    Label("shell_social_more_actions", systemImage: "plus.circle")
                }
            }
        }
        .task { await model.observeCounts() }
        .task(id: "\(model.tab)-\(model.generation)") { await model.observeList() }
        .onDisappear { model.leave() }
        .sheet(item: $holding) { action in holdSheet(action) }
    }

    @ViewBuilder
    private var content: some View {
        let list = model.list
        let rows = model.rows
        if !rows.isEmpty {
            if let stale = list.staleError {
                PulsoErrorBanner(stale) { Task { await list.refresh() } }
            }
            ForEach(rows) { row in
                connectionRow(row)
                    .onAppear { model.loadMore(after: row) }
            }
            if list.isLoadingMore { ProgressView().frame(maxWidth: .infinity) }
        } else if list.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
        } else {
            PulsoEmptyState(Text(emptyTitle(model.tab)), description: Text(emptyHint(model.tab))) {
                if model.tab == .friends {
                    NavigationLink("shell_social_add_friend_title", value: NearRoute.addFriend).buttonStyle(.pulso())
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func connectionRow(_ row: SocialConnectionRowUi) -> some View {
        HStack(spacing: 12) {
            Button {
                // 好友点开聊天（第一次用时建会话）；不能发消息时打开主页。
                if model.tab == .friends, row.canMessage { openChat(row) } else { shell?.push(NearRoute.socialProfile(profileId: row.profileId)) }
            } label: {
                HStack(spacing: 12) {
                    PulsoAvatar(url: row.avatarURL, size: 48, fallbackText: row.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(verbatim: row.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let badge = row.badge {
                                let tint: Color = badge == .friend ? .green : .accentColor
                                Text((badge == .friend ? "shell_social_friends_tag" : "shell_social_badge_mutual") as LocalizedStringKey)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .background(tint.opacity(0.12), in: .capsule)
                                    .foregroundStyle(tint)
                            }
                        }
                        let meta = [row.username.map { "@\($0)" }, row.location].compactMap { $0 }
                        if !meta.isEmpty {
                            Label {
                                Text(verbatim: meta.joined(separator: " · "))
                            } icon: {
                                if row.location != nil { Image(systemName: "mappin") }
                            }
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let bio = row.bio { Text(verbatim: bio).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        FavoriteActivityChips(activities: row.favoriteActivities)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            if model.tab == .following {
                let followed = !model.unfollowedIds.contains(row.profileId)
                Button { Task { await model.toggleFollowing(row) } } label: {
                    Image(systemName: followed ? "heart.fill" : "heart").foregroundStyle(followed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .disabled(model.busyId == row.profileId)
                .accessibilityLabel(Text((followed ? "shell_social_unfollow" : "shell_social_follow") as LocalizedStringKey))
            }
            Menu { menu(row) } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 32)
            }
            .accessibilityLabel(Text(verbatim: localizedFormat("shell_social_more", row.displayName)))
        }
    }

    @ViewBuilder
    private func menu(_ row: SocialConnectionRowUi) -> some View {
        if model.tab == .friends {
            NavigationLink(value: NearRoute.socialProfile(profileId: row.profileId)) { Label("shell_social_profile_title", systemImage: "person") }
        }
        if model.tab == .followers {
            if row.isFollowing {
                Button { Task { await model.unfollow(row) } } label: { Label("shell_social_unfollow", systemImage: "heart") }
            } else {
                Button { Task { await model.follow(row) } } label: { Label("shell_social_follow_back", systemImage: "heart.fill") }
            }
        }
        if row.canMessage {
            Button { openChat(row) } label: { Label("shell_social_message", systemImage: "bubble.left") }
        }
        if row.canSendFriendRequest {
            Button { Task { await model.addFriend(row) } } label: { Label("shell_social_add_friend", systemImage: "person.badge.plus") }
        }
        if let username = row.username {
            Button { UIPasteboard.general.string = username } label: { Label("shell_social_copy_username", systemImage: "doc.on.doc") }
        }
        if model.tab == .followers {
            Button(role: .destructive) { holding = SocialHoldAction(kind: .removeFollower, row: row) } label: { Label("shell_social_remove_follower", systemImage: "person.badge.minus") }
        }
        if model.tab == .friends {
            Button(role: .destructive) { holding = SocialHoldAction(kind: .removeFriend, row: row) } label: { Label("shell_social_remove_friend", systemImage: "person.badge.minus") }
        }
        Button(role: .destructive) { holding = SocialHoldAction(kind: .block, row: row) } label: { Label("shell_social_block", systemImage: "nosign") }
    }

    /** 按住确认（Android `holdConfirm`）。 */
    private func holdSheet(_ action: SocialHoldAction) -> some View {
        let (title, body, label): (LocalizedStringKey, String, LocalizedStringKey) = switch action.kind {
        case .removeFriend: ("shell_social_remove_friend_title", localizedFormat("shell_social_remove_friend_message", action.row.displayName), "shell_social_remove_friend")
        case .removeFollower: ("shell_social_remove_follower_title", localizedFormat("shell_social_remove_follower_message", action.row.displayName), "shell_social_remove_follower")
        case .block: ("shell_social_block_title", localizedFormat("shell_social_block_message", action.row.displayName), "shell_social_block")
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            Text(verbatim: body).foregroundStyle(.secondary)
            PulsoHoldButton(label, loading: model.busyId == action.row.profileId) {
                Task {
                    switch action.kind {
                    case .removeFriend: await model.removeFriend(action.row)
                    case .removeFollower: await model.removeFollower(action.row)
                    case .block: await model.block(action.row)
                    }
                    holding = nil
                }
            }
        }
        .padding(24)
        .presentationDetents([.height(240)])
    }

    private func openChat(_ row: SocialConnectionRowUi) {
        Task {
            if let conversationId = await model.openChat(row) {
                shell?.push(NearRoute.conversation(conversationId: conversationId, isGroup: false))
            }
        }
    }

    private func tabLabel(_ tab: SocialConnectionsTab) -> LocalizedStringKey {
        switch tab {
        case .friends: "shell_social_tab_friends"
        case .following: "shell_social_tab_following"
        case .followers: "shell_social_tab_followers"
        }
    }

    private func totalLabel(_ tab: SocialConnectionsTab) -> String.LocalizationValue {
        switch tab {
        case .following: "shell_social_stat_following"
        case .followers: "shell_social_stat_followers"
        case .friends: "shell_social_stat_friends"
        }
    }

    private func emptyTitle(_ tab: SocialConnectionsTab) -> LocalizedStringKey {
        switch tab {
        case .friends: "shell_social_friends_empty"
        case .following: "shell_social_following_empty"
        case .followers: "shell_social_followers_empty"
        }
    }

    private func emptyHint(_ tab: SocialConnectionsTab) -> LocalizedStringKey {
        switch tab {
        case .friends: "shell_social_friends_empty_hint"
        case .following: "shell_social_following_empty_hint"
        case .followers: "shell_social_followers_empty_hint"
        }
    }
}
