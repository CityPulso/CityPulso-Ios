import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI

/** 名字旁边的小标签（Android `ConnectionBadge`）。 */
enum ConnectionBadge {
    case friend
    case mutual
}

/** 关系列表里的一个人（好友 / 关注 / 粉丝共用，Android `SocialConnectionRowUi`）；空字段为 nil。 */
struct SocialConnectionRowUi: Identifiable {
    let relationId: String
    let profileId: String
    let displayName: String
    let avatarURL: URL?
    var profileScope: ProfileKind = .community
    /** 自己设过的用户名；还是默认值时 nil。 */
    var username: String?
    var location: String?
    var bio: String?
    var favoriteSports: [FavoriteSport] = []
    var badge: ConnectionBadge?
    /** 我关注了 TA（粉丝页的菜单给「取消关注」而不是「回关」）。 */
    var isFollowing = false
    /** 服务端按对方隐私设置算出。 */
    var canMessage = false
    var canSendFriendRequest = false

    var id: String { relationId }
}

/**
 * 好友 / 关注 / 粉丝和三个数字（Android `SocialOverviewViewModel`）：默认视图以本地库为准（离线优先），
 * 搜索或「最早的在前」只走网络；每个数字各自加载。
 */
@MainActor
@Observable
final class SocialOverviewModel {
    private static let searchDebounce = Duration.milliseconds(300)

    private(set) var tab: SocialConnectionsTab
    var query = "" {
        didSet { if query != oldValue { scheduleFilter() } }
    }

    var sort = SocialRelationSort.fallback {
        didSet { if sort != oldValue { applyFilter() } }
    }

    private(set) var busyId: String?
    /** 关注页点心形取消的人：先留在列表里（空心，点了重新关注），换标签或离开页面后关注列表再重拉。 */
    private(set) var unfollowedIds: Set<String> = []
    private(set) var counts: [SocialConnectionsTab: Int] = [:]
    private(set) var friends: any PagedRows<FriendItem>
    private(set) var following: any PagedRows<FollowingItem>
    private(set) var followers: any PagedRows<FollowerItem>
    /** 换一次筛选加一，页面按它重新订阅列表。 */
    private(set) var generation = 0

    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let owner: String
    @ObservationIgnored private var filter = SocialRelationFilter()
    @ObservationIgnored private var debounce: Task<Void, Never>?

    init(initialTab: SocialConnectionsTab) {
        tab = initialTab
        owner = Container.shared.authSessionStore().state.value.currentProfileId
        let service = Container.shared.socialService()
        friends = service.pageFriends(owner)
        following = service.pageFollowing(owner)
        followers = service.pageFollowers(owner)
    }

    /* ------------------------------ 订阅 ------------------------------ */

    func observeCounts() async {
        await concurrently(SocialConnectionsTab.allCases.map { tab in
            {
                for await count in self.socialService.relationCount(tab) {
                    if let count { self.counts[tab] = count }
                }
            }
        })
    }

    /** 只订阅当前标签的列表。 */
    func observeList() async {
        switch tab {
        case .friends: await friends.observe()
        case .following: await following.observe()
        case .followers: await followers.observe()
        }
    }

    func refresh() async {
        switch tab {
        case .friends: await friends.refresh()
        case .following: await following.refresh()
        case .followers: await followers.refresh()
        }
    }

    func selectTab(_ next: SocialConnectionsTab) {
        tab = next
        settleUnfollowed()
    }

    /** 离开页面：被取消关注的人从关注列表里去掉。 */
    func leave() {
        settleUnfollowed()
    }

    /** 打字停下来才问服务端。 */
    private func scheduleFilter() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            applyFilter()
        }
    }

    private func applyFilter() {
        let next = SocialRelationFilter(keyword: query.trimmingCharacters(in: .whitespaces), sort: sort)
        guard next != filter else { return }
        filter = next
        friends = socialService.pageFriends(owner, next)
        following = socialService.pageFollowing(owner, next)
        followers = socialService.pageFollowers(owner, next)
        generation += 1
    }

    private func settleUnfollowed() {
        guard !unfollowedIds.isEmpty else { return }
        unfollowedIds = []
        socialService.refreshFollowing()
    }

    /* ------------------------------ 行 ------------------------------ */

    var rows: [SocialConnectionRowUi] {
        switch tab {
        case .friends: friends.items.map(friendRow)
        case .following: following.items.map(followingRow)
        case .followers: followers.items.map(followerRow)
        }
    }

    var list: any PagedRows {
        switch tab {
        case .friends: friends
        case .following: following
        case .followers: followers
        }
    }

    func loadMore(after row: SocialConnectionRowUi) {
        guard row.relationId == rows.last?.relationId else { return }
        list.loadMore()
    }

    private func base(_ card: SocialProfileCard, _ relationId: String, _ profileId: String, _ scope: ProfileKind) -> SocialConnectionRowUi {
        let location = [card.city, card.country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SocialConnectionRowUi(
            relationId: relationId,
            profileId: profileId,
            displayName: card.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(profileId.prefix(8)),
            avatarURL: ImageURLs.image(card.avatarImageId, base: config.apiBaseURL),
            profileScope: scope,
            username: card.username,
            location: location.isEmpty ? nil : location,
            bio: card.bio.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            favoriteSports: card.favoriteSports
        )
    }

    private func friendRow(_ item: FriendItem) -> SocialConnectionRowUi {
        var row = base(item.profile, item.friendshipId, item.friendProfileId, item.friendProfileScope)
        row.canMessage = item.canMessage
        return row
    }

    private func followingRow(_ item: FollowingItem) -> SocialConnectionRowUi {
        var row = base(item.profile, item.followingProfileId, item.followingProfileId, item.followingProfileScope)
        row.badge = item.isFriend ? .friend : (item.isFollowed ? .mutual : nil)
        row.isFollowing = true
        row.canMessage = item.canMessage
        row.canSendFriendRequest = item.canSendFriendRequest
        return row
    }

    private func followerRow(_ item: FollowerItem) -> SocialConnectionRowUi {
        var row = base(item.profile, item.followerProfileId, item.followerProfileId, item.followerProfileScope)
        row.badge = item.isFriend ? .friend : nil
        row.isFollowing = item.isFollowing
        row.canMessage = item.canMessage
        row.canSendFriendRequest = item.canSendFriendRequest
        return row
    }

    /* ------------------------------ 操作 ------------------------------ */

    func follow(_ row: SocialConnectionRowUi) async {
        await act(row, "shell_social_profile_follow_failed") { try await self.socialService.follow(row.profileId, row.profileScope) }
    }

    func unfollow(_ row: SocialConnectionRowUi) async {
        await act(row, "shell_social_profile_follow_failed") { try await self.socialService.unfollow(row.profileId, row.profileScope) }
    }

    func removeFollower(_ row: SocialConnectionRowUi) async {
        await act(row, "shell_social_action_failed") { try await self.socialService.removeFollower(row.profileId, row.profileScope) }
    }

    func removeFriend(_ row: SocialConnectionRowUi) async {
        await act(row, "shell_social_action_failed") { try await self.socialService.removeFriend(row.profileId, row.profileScope) }
    }

    func block(_ row: SocialConnectionRowUi) async {
        await act(row, "shell_social_action_failed") { try await self.socialService.block(row.profileId, row.profileScope) }
    }

    /** 关注页的心形；行一直留着，直到 [settleUnfollowed]。 */
    func toggleFollowing(_ row: SocialConnectionRowUi) async {
        let unfollowed = unfollowedIds.contains(row.profileId)
        await act(row, "shell_social_profile_follow_failed") {
            if unfollowed {
                try await self.socialService.follow(row.profileId, row.profileScope, refreshFollowing: false)
                self.unfollowedIds.remove(row.profileId)
            } else {
                try await self.socialService.unfollow(row.profileId, row.profileScope, refreshFollowing: false)
                self.unfollowedIds.insert(row.profileId)
            }
        }
    }

    func addFriend(_ row: SocialConnectionRowUi) async {
        await act(row, "shell_social_profile_request_failed") {
            _ = try await self.socialService.sendFriendRequest(SendFriendRequestRequest(targetProfileId: row.profileId, targetProfileScope: row.profileScope))
            PulsoMessageCenter.shared.success("shell_social_profile_request_sent")
        }
    }

    /** 私聊（第一次用时建会话），返回会话 id。 */
    func openChat(_ row: SocialConnectionRowUi) async -> String? {
        guard busyId == nil else { return nil }
        busyId = row.profileId
        defer { busyId = nil }
        do {
            return try await communicationService.createDirectConversation(CreateDirectRequest(peerProfileId: row.profileId, peerProfileScope: row.profileScope)).conversationId
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_create_failed")
            return nil
        }
    }

    private func act(_ row: SocialConnectionRowUi, _ failure: String.LocalizationValue, _ block: @escaping () async throws -> Void) async {
        guard busyId == nil else { return }
        busyId = row.profileId
        defer { busyId = nil }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: failure)
        }
    }
}
