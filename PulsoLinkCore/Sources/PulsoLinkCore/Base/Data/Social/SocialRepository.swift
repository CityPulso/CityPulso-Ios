import Foundation

/** 社交仓储（Android `SocialRepository`）——方法与 WEB `ApiSocialRepository` 逐一对齐。 */
public struct SocialRepository: Sendable {
    private let api: SocialAPI

    public init(api: SocialAPI) {
        self.api = api
    }

    public func getFollowingCount() async throws -> Int { try await api.getFollowingCount().dataOrThrow("GetFollowingCount").count }
    public func getFollowerCount() async throws -> Int { try await api.getFollowerCount().dataOrThrow("GetFollowerCount").count }
    public func getFriendCount() async throws -> Int { try await api.getFriendCount().dataOrThrow("GetFriendCount").count }
    public func getBlockedCount() async throws -> Int { try await api.getBlockedCount().dataOrThrow("GetBlockedCount").count }

    public func getProfileRelationStats(_ profileId: String, _ profileScope: ProfileKind) async throws -> ProfileRelationStats {
        try await api.getProfileRelationStats(profileId: profileId, profileScope: profileScope.rawValue).dataOrThrow("GetProfileRelationStats")
    }

    public func listFollowing(_ body: SocialPaginationRequest = SocialPaginationRequest()) async throws -> ListWithTotal<FollowingItem> {
        try await api.listFollowing(body).dataOrThrow("ListFollowing")
    }

    public func listFollowers(_ body: SocialPaginationRequest = SocialPaginationRequest()) async throws -> ListWithTotal<FollowerItem> {
        try await api.listFollowers(body).dataOrThrow("ListFollowers")
    }

    public func listFriends(_ body: SocialPaginationRequest = SocialPaginationRequest()) async throws -> ListWithTotal<FriendItem> {
        try await api.listFriends(body).dataOrThrow("ListFriends")
    }

    public func listBlocked(_ body: SocialPaginationRequest = SocialPaginationRequest()) async throws -> ListWithTotal<BlockedItem> {
        try await api.listBlocked(body).dataOrThrow("ListBlocked")
    }

    public func checkIncomingFriendRequests() async throws -> IncomingFriendRequestCheck {
        try await api.checkIncomingFriendRequests().dataOrThrow("CheckIncomingFriendRequests")
    }

    public func listFriendRequests(_ body: FriendRequestListRequest = FriendRequestListRequest()) async throws -> ListWithTotal<FriendRequestItem> {
        try await api.listFriendRequests(body).dataOrThrow("ListFriendRequests")
    }

    public func followProfile(_ body: SocialTargetProfile) async throws { try await api.followProfile(body) }

    public func unfollowProfile(_ targetProfileId: String, _ targetProfileScope: ProfileKind) async throws {
        try await api.unfollowProfile(targetProfileId: targetProfileId, targetProfileScope: targetProfileScope.rawValue)
    }

    public func removeFollower(_ targetProfileId: String, _ targetProfileScope: ProfileKind) async throws {
        try await api.removeFollower(targetProfileId: targetProfileId, targetProfileScope: targetProfileScope.rawValue)
    }

    public func removeFriend(_ targetProfileId: String, _ targetProfileScope: ProfileKind) async throws {
        try await api.removeFriend(targetProfileId: targetProfileId, targetProfileScope: targetProfileScope.rawValue)
    }

    public func sendFriendRequest(_ body: SendFriendRequestRequest) async throws -> SendFriendRequestResponse {
        try await api.sendFriendRequest(body).dataOrThrow("SendFriendRequest")
    }

    public func acceptFriendRequest(_ friendRequestId: String) async throws { try await api.acceptFriendRequest(friendRequestId: friendRequestId) }
    public func rejectFriendRequest(_ friendRequestId: String) async throws { try await api.rejectFriendRequest(friendRequestId: friendRequestId) }
    public func cancelFriendRequest(_ friendRequestId: String) async throws { try await api.cancelFriendRequest(friendRequestId: friendRequestId) }
    public func blockProfile(_ body: BlockRequest) async throws { try await api.blockProfile(body) }

    public func unblockProfile(_ targetProfileId: String, _ targetProfileScope: ProfileKind) async throws {
        try await api.unblockProfile(targetProfileId: targetProfileId, targetProfileScope: targetProfileScope.rawValue)
    }

    public func batchGetRelationStatus(_ body: BatchRelationStatusRequest) async throws -> BatchRelationStatusResponse {
        try await api.batchGetRelationStatus(body).dataOrThrow("BatchGetRelationStatus")
    }

    public func getSocialPrivacySettings() async throws -> PrivacySettings {
        try await api.getSocialPrivacySettings().dataOrThrow("GetSocialPrivacySettings")
    }

    public func updateSocialPrivacySettings(_ body: UpdatePrivacySettingsRequest) async throws -> PrivacySettings {
        try await api.updateSocialPrivacySettings(body).dataOrThrow("UpdateSocialPrivacySettings")
    }
}
