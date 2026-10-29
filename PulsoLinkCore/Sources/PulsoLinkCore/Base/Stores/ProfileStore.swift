import Foundation

/**
 * 当前档案内存态（对应 WEB SharedDataBootstrap 落到 store 的账号聚合）。
 * 由 [ProfileBootstrap] 在登录成功 / 会话恢复后填充。
 */
public final class ProfileStore: Sendable {
    public let current = StateBroadcast<CurrentFullAccountInformation?>(nil)

    public init() {}

    public func set(_ info: CurrentFullAccountInformation) {
        current.set(info)
    }

    public func clear() {
        current.set(nil)
    }
}

/* ------------------------------ 便捷读取 ------------------------------ */

extension CurrentFullAccountInformation {
    public var kind: ProfileKind {
        switch self {
        case .community: .community
        case .organization: .organization
        case .authority: .authority
        }
    }

    public var account: Account {
        switch self {
        case let .community(value): value.account
        case let .organization(value): value.account
        case let .authority(value): value.account
        }
    }

    public var accountId: String { account.id }
    public var accountCreatedAt: String { account.createdAt }
    public var accountStatus: String { account.accountStatus }

    public var emails: [EmailItem] {
        switch self {
        case let .community(value): value.emails
        case let .organization(value): value.emails
        case let .authority(value): value.emails
        }
    }

    public var phones: [PhoneItem] {
        switch self {
        case let .community(value): value.phones
        case let .organization(value): value.phones
        case let .authority(value): value.phones
        }
    }

    /** Primary phone, else the first one (WEB CheckoutPanel prefill rule). */
    public var primaryPhone: String? { (phones.first { $0.isPrimary } ?? phones.first)?.phone }
    public var primaryEmail: String? { (emails.first { $0.isPrimary } ?? emails.first)?.email }

    /** 当前身份的公共字段（三种身份字段镜像但类型独立）。 */
    private var shared: SharedProfileFields? {
        switch self {
        case let .community(value): value.communityProfile.map(SharedProfileFields.init)
        case let .organization(value): value.organizationProfile.map(SharedProfileFields.init)
        case let .authority(value): value.authorityProfile.map(SharedProfileFields.init)
        }
    }

    public var profileId: String? { shared?.profileId }
    public var citypulsoId: String? { shared?.citypulsoId }
    /** 当前 profile 上的服务端 preference；nil 表示服务端尚未写入。 */
    public var preference: Preference? { shared?.preference }
    public var displayName: String? { shared?.displayName }
    public var firstName: String? { shared?.firstName }
    public var lastName: String? { shared?.lastName }
    public var bio: String? { shared?.bio }
    public var city: String? { shared?.city }
    public var country: String? { shared?.country }
    public var website: String? { shared?.website }
    public var timezone: String? { shared?.timezone }
    public var birthday: String? { shared?.birthday }
    public var gender: String? { shared?.gender }
    public var profileLanguage: PulsoLanguage? { shared?.profileLanguage }
    public var backgrounds: [ProfileBackground] { (shared?.backgrounds ?? []).sorted { $0.sortOrder < $1.sortOrder } }

    public var fullName: String? {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /** 当前生效头像的 asset image id（优先 isActive，退化取第一张）。 */
    public var avatarImageId: String? {
        let avatars = shared?.avatars ?? []
        return (avatars.first { $0.isActive } ?? avatars.first)?.imageId
    }

    /** 社区档角色（pulser / creator / coach …）；非社区档为空。 */
    public var communityRoles: [AuthCommunityRole] {
        if case let .community(value) = self { value.communityProfile?.communityRoles ?? [] } else { [] }
    }

    /** 组织档角色（operator / merchant）；非组织档为空。 */
    public var organizationRoles: [AuthOrganizationRole] {
        if case let .organization(value) = self { value.organizationProfile?.organizationRoles ?? [] } else { [] }
    }

    /** Favorite sports; only community profiles have them. */
    public var favoriteSports: [FavoriteSport] {
        if case let .community(value) = self { value.communityProfile?.favoriteSports ?? [] } else { [] }
    }

    /** Favorite Near activities; only community profiles have them. */
    public var favoriteActivities: [FavoriteActivity] {
        if case let .community(value) = self { value.communityProfile?.favoriteActivities ?? [] } else { [] }
    }

    /** Only community profiles holding the pulser role may book courts or join events. */
    public var isPulser: Bool { communityRoles.contains(.pulser) }

    public var roleLabels: [String] {
        switch self {
        case let .community(value): (value.communityProfile?.communityRoles ?? []).map(\.rawValue)
        case let .organization(value): (value.organizationProfile?.organizationRoles ?? []).map(\.rawValue)
        case let .authority(value): (value.authorityProfile?.authorityRoles ?? []).map(\.rawValue)
        }
    }
}

private struct SharedProfileFields {
    let profileId: String
    let citypulsoId: String
    let preference: Preference?
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let bio: String?
    let city: String?
    let country: String?
    let website: String?
    let timezone: String?
    let birthday: String?
    let gender: String?
    let profileLanguage: PulsoLanguage
    let avatars: [ProfileAvatar]
    let backgrounds: [ProfileBackground]

    init(_ p: CommunityProfile) {
        self.init(p.profileId, p.citypulsoId, p.preference, p.displayName, p.firstName, p.lastName, p.bio, p.city, p.country,
                  p.website, p.timezone, p.birthday, p.gender, p.profileLanguage, p.avatars, p.backgrounds)
    }

    init(_ p: OrganizationProfile) {
        self.init(p.profileId, p.citypulsoId, p.preference, p.displayName, p.firstName, p.lastName, p.bio, p.city, p.country,
                  p.website, p.timezone, p.birthday, p.gender, p.profileLanguage, p.avatars, p.backgrounds)
    }

    init(_ p: AuthorityProfile) {
        self.init(p.profileId, p.citypulsoId, p.preference, p.displayName, p.firstName, p.lastName, p.bio, p.city, p.country,
                  p.website, p.timezone, p.birthday, p.gender, p.profileLanguage, p.avatars, p.backgrounds)
    }

    private init(
        _ profileId: String, _ citypulsoId: String, _ preference: Preference?, _ displayName: String?,
        _ firstName: String?, _ lastName: String?, _ bio: String?, _ city: String?, _ country: String?,
        _ website: String?, _ timezone: String?, _ birthday: String?, _ gender: String?,
        _ profileLanguage: PulsoLanguage, _ avatars: [ProfileAvatar], _ backgrounds: [ProfileBackground]
    ) {
        self.profileId = profileId
        self.citypulsoId = citypulsoId
        self.preference = preference
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.bio = bio
        self.city = city
        self.country = country
        self.website = website
        self.timezone = timezone
        self.birthday = birthday
        self.gender = gender
        self.profileLanguage = profileLanguage
        self.avatars = avatars
        self.backgrounds = backgrounds
    }
}
