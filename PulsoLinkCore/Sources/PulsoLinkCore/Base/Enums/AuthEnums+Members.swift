/* Android `AuthEnums.kt` 里枚举 companion 的常量与函数（生成器只生成取值本身）。 */

extension AuthCommunityRole {
    /** 通过角色申请获得的社区角色（与 Link `AuthCommunityRolesApplicable` 一致）。 */
    public static let applicable: [AuthCommunityRole] = [.creator, .coach]
}

extension AuthApplicationKind {
    /** 社区角色申请对应的申请种类；pulser 不经申请获得。 */
    public static func of(communityRole role: AuthCommunityRole) -> AuthApplicationKind {
        switch role {
        case .creator: .creator
        case .coach: .coach
        case .pulser: preconditionFailure("pulser is never applied for")
        }
    }
}

extension FavoriteSport {
    /** 最多选几项。 */
    public static let max = 3
}

extension FavoriteActivity {
    /** 最多选几项。 */
    public static let max = 3
}
