import BetterCodable
import Foundation

/*
 * 认证域 profile DTO——与 PulsoLink-Package `types/domain/auth/profile.ts` 逐一对齐。
 * API 外层 wire 为 snake_case；preference 树在服务端按 camelCase 存，[WireCoding] 的
 * convertFromSnakeCase 对不含下划线的键原样保留，两种写法都能读。
 */

/* ------------------------------ Request ------------------------------ */

/** PATCH /auth/me/{kind}-profile——只带变更字段（nil 不写出）。 */
public struct PatchProfileRequest: Encodable, Sendable {
    public var profileLanguage: PulsoLanguage?
    public var displayName: String?
    public var firstName: String?
    public var lastName: String?
    public var country: String?
    public var city: String?
    public var gender: String?
    public var birthday: String?
    public var website: String?
    public var timezone: String?
    public var bio: String?
    /** Community profile only: replaces the list (an empty list clears it). */
    public var favoriteSports: [FavoriteSport]?
    /** Community profile only: replaces the list (an empty list clears it). */
    public var favoriteActivities: [FavoriteActivity]?

    public init() {}
}

/** PATCH /auth/me/profile-settings 请求 */
public struct PatchProfileSettingsRequest: Encodable, Sendable {
    public let loginNotification: Bool?

    public init(loginNotification: Bool?) {
        self.loginNotification = loginNotification
    }
}

/** 确认背景图单项 */
public struct ConfirmProfileBackgroundItem: Encodable, Sendable {
    public let imageId: String
    public let sortOrder: Int

    public init(imageId: String, sortOrder: Int) {
        self.imageId = imageId
        self.sortOrder = sortOrder
    }
}

/** PUT /auth/me/{kind}-profile/backgrounds 请求 */
public struct ConfirmProfileBackgroundsRequest: Encodable, Sendable {
    public let images: [ConfirmProfileBackgroundItem]

    public init(images: [ConfirmProfileBackgroundItem]) {
        self.images = images
    }
}

/**
 * POST /auth/profiles/lookup——单一 scope 内精确找人；后端并行匹配
 * profile_id（仅 UUID）、citypulso_id（区分大小写）与 display_name，不搜真实姓名。
 */
public struct LookupProfilesRequest: Encodable, Sendable {
    public let profileScope: ProfileKind
    public let keyword: String

    public init(profileScope: ProfileKind, keyword: String) {
        self.profileScope = profileScope
        self.keyword = keyword
    }
}

/** PUT /auth/me/citypulso-id——修改当前 profile 的 citypulso_id。 */
public struct UpdateCitypulsoIdRequest: Encodable, Sendable {
    public let citypulsoId: String

    public init(citypulsoId: String) {
        self.citypulsoId = citypulsoId
    }
}

/** 与 API `citypulso_id` 校验一致（WEB `CITYPULSO_ID_PATTERN`）。 */
public var citypulsoIdPattern: Regex<Substring> { /^[A-Za-z0-9_!.\-]{4,64}$/ }

/* --------------------------- Preference 树 --------------------------- */

/** 地图偏好（PulsoLink 各产品共享）。 */
public struct MapPreference: Codable, Sendable, Hashable {
    public var mapLightStyle: MapLightColor?
    public var mapDarkStyle: MapDarkColor?
    public var map3d: Bool?
    /** Explore 等全屏地图：true 为 2D 俯视，false 为倾斜 3D 视角 */
    public var mapflat: Bool?
    /** Explore 活动卡片。缺省为不显示。显式 true/false 会同步到两端。 */
    public var showEventCards: Bool?
    /** Explore 球馆卡片。缺省为不显示。显式 true/false 会同步到两端。 */
    public var showVenueCards: Bool?
    public var locationRing: String?
    public var locationDot: String?
    public var locationBorder: String?
    public var locationAvatarUseImage: Bool?
    public var locationAvatarBg: String?
    public var locationAvatarBorder: String?
    public var locationAvatarChar: String?
}

/** 事件模块偏好。 */
public struct EventPreference: Codable, Sendable, Hashable {
    public var hiddenNearModules: [NearActivityType]?
    public var hiddenLoopModules: [LoopEventType]?
    public var nearbyPageSize: Int?
    public var nearbyRadiusMinM: Int?
    public var nearbyRadiusMaxM: Int?
}

/** 账单偏好。 */
public struct BillingPreference: Codable, Sendable, Hashable {
    public var receiptPosition: BillingReceiptPosition?
}

/**
 * 单个底栏槽：页面 + 图标组（wire `{ "destination", "icon" }`，值为 Android 枚举名）。
 * 非对象 / 未知页面 → 空槽，[resolveNavPreference] 回落该槽默认；未知图标 → 页默认图标组。
 */
public struct AndroidNavSlot: Codable, Sendable, Hashable {
    public var destination: ShellDestination?
    public var icon: ShellNavIconPack?

    public init(destination: ShellDestination? = nil, icon: ShellNavIconPack? = nil) {
        self.destination = destination
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case destination, icon
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let destination = ShellDestination.fromWire(try? container.decodeIfPresent(String.self, forKey: .destination))
        else {
            self.init()
            return
        }
        let icon = ShellNavIconPack.fromWire(try? container.decodeIfPresent(String.self, forKey: .icon))
        self.init(destination: destination, icon: icon ?? destination.defaultIconPack)
    }
}

/**
 * 手机底栏导航偏好（槽 5 固定 Apps，不存）。iOS 与 Android 共用这一份，两端手机底栏一致。
 * 桌面图标各 app 一份：Loop 只读 loop，Near 只读 near。
 */
public struct AndroidPreference: Codable, Sendable, Hashable {
    public var slot1: AndroidNavSlot?
    public var slot2: AndroidNavSlot?
    public var slot3: AndroidNavSlot?
    public var slot4: AndroidNavSlot?
    public var slot6: AndroidNavSlot?
    public var loopLauncherIcon: LauncherIcon?
    public var nearLauncherIcon: LauncherIcon?
}

/** 共享 Radix Themes 外观偏好（iOS 只用 accent 与 appearance，其余原样保留并回传）。 */
public struct ThemePreference: Codable, Sendable, Hashable {
    public var accent: ThemeAccentColor?
    public var gray: ThemeGrayColor?
    public var appearance: ThemeAppearance?
    public var radius: ThemeRadius?
    public var scaling: ThemeScaling?
    public var panelBackground: ThemePanelBackground?
    public var fontFamily: ThemeFontFamily?
}

/** 收藏联动。缺省的「加上」为 true，「取消」为 false。 */
public struct FavoritePreference: Codable, Sendable, Hashable {
    public var autoOnVenueAction: Bool?
    public var withVenueWhenBuilding: Bool?
    public var withBuildingWhenVenue: Bool?
    public var withoutVenueWhenBuilding: Bool?
    public var withoutBuildingWhenVenue: Bool?
}

/** profile.preference JSON 聚合。 */
public struct Preference: Codable, Sendable, Hashable {
    public var theme: ThemePreference?
    public var language: PulsoLanguage?
    public var map: MapPreference?
    public var event: EventPreference?
    public var billing: BillingPreference?
    public var favorite: FavoritePreference?
    public var android: AndroidPreference?
}

/* ------------------------------ Response ------------------------------ */

/** 账号（auth.Accounts）。 */
public struct Account: Codable, Sendable, Hashable {
    public let id: String
    public let accountStatus: String
    public let signupPlatform: AuthSignupPlatform
    public let createdAt: String
    public let updatedAt: String
}

/** 与后端 auth.EmailItemVO 一致。 */
public struct EmailItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let accountId: String
    public let email: String
    public let isPrimary: Bool
    public let verifiedAt: String?
    public let createdAt: String
    public let updatedAt: String
}

/** 电话（auth.Phones）。 */
public struct PhoneItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let accountId: String
    public let phone: String
    public let isPrimary: Bool
    public let verifiedAt: String?
    public let createdAt: String
    public let updatedAt: String
}

/** profile 头像行。 */
public struct ProfileAvatar: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let profileId: String
    public let imageId: String
    public let isActive: Bool
    public let createdAt: String
    public let updatedAt: String
}

/** profile 背景图行。 */
public struct ProfileBackground: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let profileId: String
    public let imageId: String
    public let sortOrder: Int
    public let createdAt: String
    public let updatedAt: String
}

/** profile 设置行。 */
public struct ProfileSettings: Codable, Sendable, Hashable {
    public let loginNotification: Bool
    public let createdAt: String
    public let updatedAt: String
}

/**
 * 社区档聚合；对应后端 CommunityProfileVO。
 * 与 [AuthorityProfile] 字段镜像但类型独立——改动一方不波及另一方（对齐 WEB 设计）。
 */
public struct CommunityProfile: Codable, Sendable, Hashable {
    public let profileId: String
    public let accountId: String
    public let citypulsoId: String
    public let profileLanguage: PulsoLanguage
    public let preference: Preference?
    public let displayName: String?
    public let firstName: String?
    public let lastName: String?
    public let country: String?
    public let city: String?
    public let gender: String?
    public let birthday: String?
    public let website: String?
    public let timezone: String?
    public let bio: String?
    public let createdAt: String
    public let updatedAt: String
    @DefaultEmptyArray public var avatars: [ProfileAvatar]
    @DefaultEmptyArray public var backgrounds: [ProfileBackground]
    public let settings: ProfileSettings?
    @DefaultEmptyArray public var communityRoles: [AuthCommunityRole]
    @DefaultEmptyArray public var favoriteSports: [FavoriteSport]
    @DefaultEmptyArray public var favoriteActivities: [FavoriteActivity]
}

/** 组织档聚合；对应后端 OrganizationProfileVO。 */
public struct OrganizationProfile: Codable, Sendable, Hashable {
    public let profileId: String
    public let accountId: String
    public let citypulsoId: String
    public let profileLanguage: PulsoLanguage
    public let preference: Preference?
    public let displayName: String?
    public let firstName: String?
    public let lastName: String?
    public let country: String?
    public let city: String?
    public let gender: String?
    public let birthday: String?
    public let website: String?
    public let timezone: String?
    public let bio: String?
    public let createdAt: String
    public let updatedAt: String
    @DefaultEmptyArray public var avatars: [ProfileAvatar]
    @DefaultEmptyArray public var backgrounds: [ProfileBackground]
    public let settings: ProfileSettings?
    @DefaultEmptyArray public var organizationRoles: [AuthOrganizationRole]
}

/** 权限档聚合；对应后端 AuthorityProfileVO。 */
public struct AuthorityProfile: Codable, Sendable, Hashable {
    public let profileId: String
    public let accountId: String
    public let citypulsoId: String
    public let profileLanguage: PulsoLanguage
    public let preference: Preference?
    public let displayName: String?
    public let firstName: String?
    public let lastName: String?
    public let country: String?
    public let city: String?
    public let gender: String?
    public let birthday: String?
    public let website: String?
    public let timezone: String?
    public let bio: String?
    public let createdAt: String
    public let updatedAt: String
    @DefaultEmptyArray public var avatars: [ProfileAvatar]
    @DefaultEmptyArray public var backgrounds: [ProfileBackground]
    public let settings: ProfileSettings?
    @DefaultEmptyArray public var authorityRoles: [AuthAuthorityRole]
}

/** 账号聚合（含账号下全部 profile），对应后端 FullAccountInformationVO。 */
public struct FullAccountInformation: Codable, Sendable, Hashable {
    public let account: Account
    @DefaultEmptyArray public var emails: [EmailItem]
    @DefaultEmptyArray public var phones: [PhoneItem]
    @DefaultEmptyArray public var communityProfiles: [CommunityProfile]
    @DefaultEmptyArray public var organizationProfiles: [OrganizationProfile]
    @DefaultEmptyArray public var authorityProfiles: [AuthorityProfile]
}

/**
 * 「当前登录态」视角的账号信息（社区档）：后端已按 token 中的 profile_id 投影成单个 profile。
 * GET /auth/me/full-account-information-with-community-profile 返回。
 */
public struct FullAccountInformationWithCommunityProfile: Codable, Sendable, Hashable {
    public let account: Account
    @DefaultEmptyArray public var emails: [EmailItem]
    @DefaultEmptyArray public var phones: [PhoneItem]
    public let communityProfile: CommunityProfile?
}

/** GET /auth/me/full-account-information-with-organization-profile 返回。 */
public struct FullAccountInformationWithOrganizationProfile: Codable, Sendable, Hashable {
    public let account: Account
    @DefaultEmptyArray public var emails: [EmailItem]
    @DefaultEmptyArray public var phones: [PhoneItem]
    public let organizationProfile: OrganizationProfile?
}

/** GET /auth/me/full-account-information-with-authority-profile 返回。 */
public struct FullAccountInformationWithAuthorityProfile: Codable, Sendable, Hashable {
    public let account: Account
    @DefaultEmptyArray public var emails: [EmailItem]
    @DefaultEmptyArray public var phones: [PhoneItem]
    public let authorityProfile: AuthorityProfile?
}

/** 与后端 auth.CommunityProfileItemVO（ListCommunityProfileItems 视图）一致。 */
public struct CommunityProfileItem: Codable, Sendable, Hashable, Identifiable {
    public let profileId: String
    public let accountId: String
    public let citypulsoId: String
    public let displayName: String?
    public let profileLanguage: PulsoLanguage
    public let city: String?
    public let country: String?
    public let website: String?
    public let bio: String?
    @DefaultEmptyArray public var favoriteSports: [FavoriteSport]
    @DefaultEmptyArray public var favoriteActivities: [FavoriteActivity]
    public let avatarImageId: String?
    public let backgroundImageId: String?
    public let createdAt: String
    @DefaultEmptyArray public var communityRoles: [AuthCommunityRole]

    public var id: String { profileId }

    /** 用户自己设过的用户名；默认值（= profileId）返回 nil。 */
    public var username: String? {
        citypulsoId.trimmingCharacters(in: .whitespaces).isEmpty || citypulsoId == profileId ? nil : citypulsoId
    }
}

/** 与后端 auth.OrganizationProfileItemVO（ListOrganizationProfileItems 视图）一致。 */
public struct OrganizationProfileItem: Codable, Sendable, Hashable, Identifiable {
    public let profileId: String
    public let accountId: String
    public let citypulsoId: String
    public let displayName: String?
    public let profileLanguage: PulsoLanguage
    public let city: String?
    public let country: String?
    public let website: String?
    public let timezone: String?
    public let birthday: String?
    public let avatarImageId: String?
    public let backgroundImageId: String?
    public let createdAt: String
    @DefaultEmptyArray public var organizationRoles: [AuthOrganizationRole]

    public var id: String { profileId }
}

/** 与后端 auth.AuthorityProfileItemVO（ListAuthorityProfileItems 视图）一致。 */
public struct AuthorityProfileItem: Codable, Sendable, Hashable, Identifiable {
    public let profileId: String
    public let accountId: String
    public let citypulsoId: String
    public let displayName: String?
    public let profileLanguage: PulsoLanguage
    public let city: String?
    public let country: String?
    public let website: String?
    public let timezone: String?
    public let birthday: String?
    public let avatarImageId: String?
    public let backgroundImageId: String?
    public let createdAt: String
    @DefaultEmptyArray public var authorityRoles: [AuthAuthorityRole]

    public var id: String { profileId }
}

/** 找人命中项（跨 scope 公开卡片；不含真实姓名）。roles 为该 scope 的角色 wire 值。 */
public struct LookupProfileItem: Codable, Sendable, Hashable, Identifiable {
    public let profileId: String
    public let profileScope: ProfileKind
    public let citypulsoId: String
    public let displayName: String?
    public let avatarImageId: String?
    public let backgroundImageId: String?
    public let city: String?
    public let country: String?
    @DefaultEmptyArray public var roles: [String]

    public var id: String { profileId }
}

public struct LookupProfilesResponse: Codable, Sendable, Hashable {
    @DefaultEmptyArray public var items: [LookupProfileItem]
}
