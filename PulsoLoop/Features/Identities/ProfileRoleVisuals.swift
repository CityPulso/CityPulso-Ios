import PulsoLinkCore
import SwiftUI

/** 角色 / 档位 wire → SF Symbol 与文案（对应 Android `ProfileRoleVisuals`）。 */
enum ProfileRoleVisuals {
    /** 头部 / 摘要的展示顺序（owner 最先）。 */
    private static let priority: [String] = [
        AuthAuthorityRole.owner.rawValue,
        AuthAuthorityRole.administrator.rawValue,
        AuthAuthorityRole.moderator.rawValue,
        AuthAuthorityRole.reviewer.rawValue,
        AuthOrganizationRole.operator.rawValue,
        AuthOrganizationRole.merchant.rawValue,
        AuthCommunityRole.coach.rawValue,
        AuthCommunityRole.creator.rawValue,
        AuthCommunityRole.pulser.rawValue,
    ]

    static func kindSymbol(_ kind: ProfileKind) -> String {
        switch kind {
        case .community: "person.3"
        case .organization: "building.2"
        case .authority: "shield"
        }
    }

    static func symbol(_ role: String) -> String {
        switch normalized(role) {
        case "pulser": "bolt"
        case "creator": "star.fill"
        case "coach": "graduationcap.fill"
        case "operator": "storefront.fill"
        case "merchant": "tag.fill"
        case "reviewer": "doc.text.magnifyingglass"
        case "moderator": "shield.fill"
        case "administrator": "person.badge.shield.checkmark.fill"
        case "owner": "crown.fill"
        default: "wrench.and.screwdriver.fill"
        }
    }

    /** 已知角色的文案 key；未知角色返回 nil，用 [displayLabel]。 */
    static func labelKey(_ role: String) -> LocalizedStringKey? {
        switch normalized(role) {
        case "owner": "profile_role_owner"
        case "administrator": "profile_role_administrator"
        case "moderator": "profile_role_moderator"
        case "reviewer": "profile_role_reviewer"
        case "pulser": "profile_role_pulser"
        case "creator": "profile_role_creator"
        case "coach": "profile_role_coach"
        case "operator": "profile_role_operator"
        case "merchant": "profile_role_merchant"
        default: nil
        }
    }

    static func displayLabel(_ role: String) -> String {
        role.split(whereSeparator: { "_- ".contains($0) }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /** 去重并按 [priority] 排序，未知角色排在最后。 */
    static func sorted(_ roles: [String]) -> [String] {
        var seen = Set<String>()
        let unique = roles.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
        return unique.sorted { (priority.firstIndex(of: $0) ?? priority.count) < (priority.firstIndex(of: $1) ?? priority.count) }
    }

    private static func normalized(_ role: String) -> String {
        role.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/** 角色胶囊：图标 + 名称。 */
struct ProfileRoleLabel: View {
    let role: String

    var body: some View {
        Label {
            if let key = ProfileRoleVisuals.labelKey(role) {
                Text(key)
            } else {
                Text(verbatim: ProfileRoleVisuals.displayLabel(role))
            }
        } icon: {
            Image(systemName: ProfileRoleVisuals.symbol(role))
        }
    }
}
