import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 公开主页（Android `SocialProfileScreen`）：封面 + 头像，名字 / 用户名 / 地点 / 简介 / 喜欢的活动类型，
 * 发起 · 关注 · 粉丝，关注 / 私信 / 加好友，发起的 / 参加的活动；右上角分享和拉黑。
 */
struct SocialProfileView: View {
    @State private var model: SocialProfileModel
    @State private var confirmingBlock = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(profileId: String) {
        _model = State(initialValue: SocialProfileModel(profileId: profileId))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.card.data == nil ? String(localized: "shell_social_profile_title") : model.displayName))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.observe() }
            .sheet(isPresented: $confirmingBlock) {
                // 按住确认（Android `holdConfirm`）。
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: localizedFormat("social_profile_block_confirm_title", model.displayName)).font(.title3.bold())
                    Text("social_profile_block_confirm_body").foregroundStyle(.secondary)
                    PulsoHoldButton("social_profile_block", loading: model.actionInProgress) {
                        Task {
                            await model.toggleBlock()
                            confirmingBlock = false
                        }
                    }
                }
                .padding(24)
                .presentationDetents([.height(240)])
            }
    }

    @ViewBuilder
    private var content: some View {
        if let card = model.card.data {
            List {
                header(card)
                Section {
                    PulsoUnderlineTabRow(SocialProfileTab.allCases, selection: $model.tab) { Text($0.labelKey) }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                switch model.tab {
                case .hosted: activities(model.hosted, empty: "shell_social_profile_hosted_empty", badge: .host)
                case .joined: activities(model.joined, empty: "social_profile_joined_empty", badge: nil)
                }
            }
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: localizedFormat("profile_overview_share_text", model.displayName)) {
                            Label("social_profile_share", systemImage: "square.and.arrow.up")
                        }
                        if !model.isCurrentUser {
                            if model.isBlockedByMe {
                                Button { Task { await model.toggleBlock() } } label: { Label("social_profile_unblock", systemImage: "nosign") }
                            } else {
                                Button(role: .destructive) { confirmingBlock = true } label: { Label("social_profile_block", systemImage: "nosign") }
                            }
                        }
                    } label: {
                        Label("social_profile_more", systemImage: "ellipsis.circle")
                    }
                }
            }
        } else if let error = model.card.error {
            PulsoLoadErrorView(error) { Task { await model.load() } }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ card: CommunityProfileItem) -> some View {
        Section {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = model.imageURL(card.backgroundImageId) {
                        PulsoRemoteImage(url: url)
                    } else {
                        Rectangle().fill(.tint.opacity(0.2))
                    }
                }
                .frame(height: 140)
                .clipped()
                PulsoAvatar(url: model.imageURL(card.avatarImageId), size: 72, fallbackText: model.displayName)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                    .padding(.leading, 16)
                    .offset(y: 36)
            }
            .padding(.bottom, 36)
            .listRowInsets(EdgeInsets())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: model.displayName).font(.title3.bold())
                    if model.isBlockedByMe { Text("social_profile_blocked_badge").font(.caption.weight(.medium)).foregroundStyle(.red) }
                }
                if let username = card.username { Text(verbatim: "@\(username)").font(.subheadline).foregroundStyle(.tint) }
                let location = [card.city, card.country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
                if !location.isEmpty { Label(location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                if let website = card.website, !website.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(verbatim: website).font(.caption).foregroundStyle(.tint)
                }
                if let bio = card.bio, !bio.trimmingCharacters(in: .whitespaces).isEmpty { Text(verbatim: bio).font(.subheadline) }
                FavoriteActivityChips(activities: card.favoriteActivities)
                stats
                if !model.isCurrentUser { actions }
            }
        }
    }

    /** 发起 · 关注 · 粉丝：关注 / 粉丝只显示数字；没公开的写「未公开」。 */
    private var stats: some View {
        HStack {
            stat(String(model.hosted.items.count), "social_profile_stat_hosted")
            stat(count(model.followingCount), "social_profile_stat_following")
            stat(count(model.followerCount), "social_profile_stat_followers")
        }
        .padding(.vertical, 6)
    }

    private func count(_ value: Int?) -> String {
        guard model.statsLoaded else { return "…" }
        return value.map(String.init) ?? String(localized: "social_profile_stat_hidden")
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack {
            Text(verbatim: value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack {
            Button {
                Task { await model.toggleFollow() }
            } label: {
                Label((model.isFollowing ? "social_profile_following" : "shell_social_follow") as LocalizedStringKey, systemImage: model.isFollowing ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pulso())
            if model.canMessage {
                Button {
                    Task {
                        if let conversationId = await model.openChat() { shell?.push(NearRoute.conversation(conversationId: conversationId, isGroup: false)) }
                    }
                } label: {
                    Image(systemName: "bubble.left")
                }
                .buttonStyle(.pulso(.soft))
                .accessibilityLabel(Text("shell_social_message"))
            }
            if !model.isFriend {
                if let direction = model.pendingDirection {
                    Button((direction == .outgoing ? "shell_social_request_sent" : "shell_social_requests") as LocalizedStringKey) {}
                        .buttonStyle(.pulso(.soft))
                        .disabled(true)
                } else if model.canSendFriendRequest {
                    Button("shell_social_add_friend") { Task { await model.sendFriendRequest() } }.buttonStyle(.pulso(.soft))
                }
            }
        }
        .disabled(model.actionInProgress)
    }

    @ViewBuilder
    private func activities(_ list: ActivitysMerge, empty: LocalizedStringKey, badge: ActivityFeedBadge?) -> some View {
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120).listRowBackground(Color.clear)
        } else if let error = list.error {
            PulsoErrorBanner(error) { Task { await model.load() } }
        } else if list.items.isEmpty {
            PulsoEmptyState(Text(empty), style: .calendar).listRowBackground(Color.clear)
        } else {
            ForEach(list.items, id: \.id) { item in
                NavigationLink(value: NearRoute.activity(activityType: item.activityType, activityId: item.id)) {
                    ActivityFeedCard(item: item, badge: badge, imageURL: model.imageURL(item.coverImageId))
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
        }
    }
}
