import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI

/**
 * 公开主页（Android `SocialProfileViewModel`）：封面 + 名片 + 关注 / 粉丝数 + 关系操作 + TA 发起 / 参加的活动（所有运动合起来）。
 * 不显示真实姓名。
 */
@MainActor
@Observable
final class SocialProfileModel {
    private static let pageSize = 50

    let profileId: String
    private(set) var card = Loadable<CommunityProfileItem>()
    private(set) var isCurrentUser = false
    private(set) var relation: RelationStatus?
    private(set) var actionInProgress = false
    /** nil：还在加载，或 TA 没公开这一项。 */
    private(set) var followingCount: Int?
    private(set) var followerCount: Int?
    private(set) var statsLoaded = false
    var tab = SocialProfileTab.hosted
    let hosted = SportEventsMerge()
    let joined = SportEventsMerge()

    @ObservationIgnored @Injected(\.authQueryStore) private var authQuery
    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.loopSportServices) private var services
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(profileId: String) {
        self.profileId = profileId
    }

    var displayName: String {
        card.data?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(profileId.prefix(8))
    }

    var isFollowing: Bool { relation?.isFollowing ?? false }
    var isFriend: Bool { relation?.isFriend ?? false }
    var isBlockedByMe: Bool { relation?.isBlockedByMe ?? false }
    var pendingDirection: SocialFriendRequestDirection? { relation?.pendingFriendRequest?.direction }
    var canMessage: Bool { relation?.canMessage ?? false }
    var canSendFriendRequest: Bool { relation?.canSendFriendRequest ?? false }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /* ------------------------------ 加载 ------------------------------ */

    func observe() async {
        await load()
        let session = sessionStore.state.value
        let profileId = profileId
        let limit = Self.pageSize
        await concurrently([
            {
                await self.hosted.observe(self.services.values.map { service in
                    service.hostedEvents(accountId: session.currentAccountId, profileId: session.currentProfileId, hostedProfileId: profileId, limit: limit)
                })
            },
            {
                await self.joined.observe(self.services.values.map { service in
                    service.profileRegistrations(profileId: profileId, limit: limit)
                })
            },
        ])
    }

    func load() async {
        card.isLoading = true
        do {
            let value = try await authQuery.publicCards.fresh(profileId)
            if profileStore.current.value?.profileId == profileId {
                isCurrentUser = true
            } else {
                let session = sessionStore.state.value
                relation = try await socialService.getRelations(RelationStatusKey(
                    accountId: session.currentAccountId, profileId: session.currentProfileId,
                    targets: [SocialTargetProfile(targetProfileId: profileId, targetProfileScope: .community)]
                )).items.first
            }
            card = Loadable(data: value, isLoading: false)
            await loadStats()
        } catch {
            card = Loadable(data: card.data, isLoading: false, error: UiError(error))
        }
    }

    /** 关注 / 粉丝数；没公开的显示「未公开」，加载失败保留上一次的数字。 */
    private func loadStats() async {
        if let stats = try? await socialService.getProfileRelationStats(profileId) {
            followingCount = stats.followingCount
            followerCount = stats.followerCount
        }
        statsLoaded = true
    }

    /* ------------------------------ 操作 ------------------------------ */

    func toggleFollow() async {
        guard !actionInProgress, !isCurrentUser else { return }
        let following = isFollowing
        await act("shell_social_profile_follow_failed") {
            if following {
                try await self.socialService.unfollow(self.profileId, .community)
            } else {
                try await self.socialService.follow(self.profileId, .community)
            }
            self.relation?.isFollowing = !following
            await self.loadStats()
        }
    }

    /** 拉黑会断掉双方所有关系，之后整页重拉。 */
    func toggleBlock() async {
        guard !actionInProgress, !isCurrentUser else { return }
        let blocked = isBlockedByMe
        await act("social_profile_block_failed") {
            if blocked {
                try await self.socialService.unblock(self.profileId, .community)
            } else {
                try await self.socialService.block(self.profileId, .community)
            }
        }
        await load()
    }

    func sendFriendRequest() async {
        guard !actionInProgress, !isCurrentUser, !isFriend, pendingDirection == nil else { return }
        await act("shell_social_profile_request_failed") {
            let response = try await self.socialService.sendFriendRequest(SendFriendRequestRequest(targetProfileId: self.profileId, targetProfileScope: .community))
            self.relation?.pendingFriendRequest = PendingFriendRequest(friendRequestId: response.friendRequestId, direction: .outgoing, status: .pending)
            self.relation?.canSendFriendRequest = false
            PulsoMessageCenter.shared.success("shell_social_profile_request_sent")
        }
    }

    /** 私聊（第一次用时建会话），返回会话 id。 */
    func openChat() async -> String? {
        guard !actionInProgress, canMessage else { return nil }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            return try await communicationService.createDirectConversation(CreateDirectRequest(peerProfileId: profileId, peerProfileScope: .community)).conversationId
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_create_failed")
            return nil
        }
    }

    private func act(_ failure: String.LocalizationValue, _ block: @escaping () async throws -> Void) async {
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: failure)
        }
    }
}

/** 把每个运动的一条活动查询合成一张列表，最新的在前（Android `mergeSportAnswers`）。 */
@MainActor
@Observable
final class SportEventsMerge {
    private(set) var items: [any SportEventItem] = []
    private(set) var isLoading = true
    private(set) var error: UiError?

    @ObservationIgnored private var bySport: [Int: [any SportEventItem]] = [:]
    @ObservationIgnored private var errors: [Int: UiError] = [:]

    func observe(_ streams: [AsyncStream<QueryResponse<[any SportEventItem]>>]) async {
        let count = streams.count
        await concurrently(streams.enumerated().map { index, stream in
            {
                for await response in stream {
                    switch response {
                    case .loading: break
                    case let .data(rows):
                        self.bySport[index] = rows
                        self.errors[index] = nil
                    case let .error(error):
                        self.errors[index] = error
                    }
                    self.publish(total: count)
                }
            }
        })
    }

    private func publish(total: Int) {
        let rows = bySport.values.flatMap { $0 }
        items = sortedByStartsAt(rows, startsAt: \.startsAt, id: \.id, descending: true)
        let answered = Set(bySport.keys).union(errors.keys).count
        isLoading = answered < total && items.isEmpty
        error = items.isEmpty && answered == total ? errors.values.first : nil
    }
}
