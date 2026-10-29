import Foundation

public struct AuthProfilesKey: Hashable, Sendable {
    public let accountId: String
    public let kind: ProfileKind

    public init(accountId: String, kind: ProfileKind) {
        self.accountId = accountId
        self.kind = kind
    }
}

/** 「我的社区角色申请」：同一社区身份按申请的角色分别定位。 */
public struct MyCommunityRoleApplicationKey: Hashable, Sendable {
    public let accountId: String
    public let profileId: String
    public let role: AuthCommunityRole

    public init(accountId: String, profileId: String, role: AuthCommunityRole) {
        self.accountId = accountId
        self.profileId = profileId
        self.role = role
    }
}

/**
 * auth 域的查询缓存（对应 Android `AuthQueryStore`）。key 带账号 id，换账号不会读到上一个账号的缓存；
 * 退出登录时全部清掉。
 */
public final class AuthQueryStore: LogoutClearable {
    /** key = 账号 id。 */
    public let emails: MemoryQuery<String, [EmailItem]>
    public let profiles: MemoryQuery<AuthProfilesKey, ProfileItemsByKind>
    /** key = 身份 id。 */
    public let publicCards: MemoryQuery<String, CommunityProfileItem>
    /** 没申请过是 nil。 */
    public let communityRoleApplications: MemoryQuery<MyCommunityRoleApplicationKey, CommunityRoleApplicationItem?>

    public init(auth: AuthRepository, authEventBus: AuthEventBus) {
        emails = MemoryQuery(invalidates: {
            authEventBus.signals { event in
                switch event {
                case .invalidateEmails, .logout: true
                default: false
                }
            }
        }) { _ in
            try await auth.listEmails().items
        }
        profiles = MemoryQuery(invalidates: {
            authEventBus.signals { event in
                switch event {
                case .invalidateProfiles, .logout: true
                default: false
                }
            }
        }) { key in
            try await auth.listProfiles(kind: key.kind)
        }
        publicCards = MemoryQuery(invalidates: {
            authEventBus.signals { event in
                switch event {
                case .updateAccountSuccess, .logout: true
                default: false
                }
            }
        }) { profileId in
            try await auth.getPublicProfileCard(profileId: profileId)
        }
        communityRoleApplications = MemoryQuery(invalidates: {
            authEventBus.signals { event in
                switch event {
                case .invalidateModerationApplications, .applicationResolved, .logout: true
                default: false
                }
            }
        }) { key in
            try await auth.getMyCommunityRoleApplication(role: key.role)
        }
    }

    public func onLogout() async throws {
        await emails.clear()
        await profiles.clear()
        await publicCards.clear()
        await communityRoleApplications.clear()
    }
}
