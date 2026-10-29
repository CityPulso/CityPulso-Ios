import BetterCodable
import Foundation

/*
 * 身份申请 DTO（我自己的申请部分）——与 Android `ModerationDtos.kt`、
 * PulsoLink-Package `types/domain/auth/moderation.ts` 对齐。审核列表 / 批准 / 驳回只在网页版，不移植。
 */

/** 社区角色申请条目（creator / coach）。 */
public struct CommunityRoleApplicationItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let applicantProfileId: String
    public let applicantAccountId: String
    public let applicantDisplayName: String?
    @DefaultEmptyArray public var applicantCommunityRoles: [AuthCommunityRole]
    public let applicantAvatarImageId: String?
    public let applicantEmail: String?
    public let role: AuthCommunityRole
    public let motivation: String?
    public let status: AuthApplicationStatus
    public let reviewerProfileId: String?
    public let rejectionReason: String?
    public let reviewedAt: String?
    public let createdAt: String
    public let updatedAt: String
}

/** POST /auth/me/community-role-applications：pulser 申请额外的社区角色（creator / coach）。 */
public struct SubmitCommunityRoleApplicationRequest: Encodable, Sendable {
    public let role: AuthCommunityRole
    public let motivation: String?

    public init(role: AuthCommunityRole, motivation: String?) {
        self.role = role
        self.motivation = motivation
    }
}
