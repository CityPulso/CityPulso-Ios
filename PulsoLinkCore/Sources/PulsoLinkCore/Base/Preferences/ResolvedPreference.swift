import Foundation

/*
 * 偏好解析层——对应 WEB `stores/preference.ts` 的 ResolvedPreference 家族：
 * 服务端 `Preference`（全可空 wire DTO）⇄ 本地已填默认值的 Resolved 形状。
 */

/* ------------------------------ 事件偏好 clamp 常量 ------------------------------ */

public enum EventPreferenceLimits {
    public static let pageSize = 1...40
    public static let radiusMinM = 10...100
    public static let radiusMaxM = 500...8000
}

/** 地图视口推导附近查询半径下限（米）。 */
public let exploreNearbyRadiusMinM = 50
/** 地图视口推导附近查询半径上限（米）；与后端 maxGeoNearRadiusM 对齐。 */
public let exploreNearbyRadiusMaxM = 3000
/** Explore 附近事件每页条数。 */
public let exploreNearbyPageSize = 40

/* ------------------------------ Resolved 形状 ------------------------------ */

/** 地图偏好（默认值已填；mapRich / mapNearbyRange 仅本地，不上传）。活动卡片与球馆卡片为空 = 不显示。 */
public struct ResolvedMapPreference: Codable, Sendable, Hashable {
    public var mapLightStyle: MapLightColor = .fallback
    public var mapDarkStyle: MapDarkColor = .fallback
    public var map3d = false
    public var mapflat = true
    public var mapRich = true
    public var mapNearbyRange = false
    /** nil 或 false：不显示活动卡片。true：地图上一直显示。 */
    public var showEventCards: Bool?
    /** nil 或 false：不显示球馆卡片。true：地图上一直显示。 */
    public var showVenueCards: Bool?
    public var locationRing: String?
    public var locationDot: String?
    public var locationBorder: String?
    public var locationAvatarUseImage: Bool?
    public var locationAvatarBg: String?
    public var locationAvatarBorder: String?
    public var locationAvatarChar: String?

    public init() {}
}

/** 事件偏好（默认值已填 + clamp）。 */
public struct ResolvedEventPreference: Codable, Sendable, Hashable {
    public var hiddenNearModules: [NearActivityType] = []
    public var hiddenLoopModules: [LoopEventType] = []
    public var nearbyPageSize = exploreNearbyPageSize
    public var nearbyRadiusMinM = exploreNearbyRadiusMinM
    public var nearbyRadiusMaxM = exploreNearbyRadiusMaxM

    public init() {}
}

/** 账单偏好（默认值已填）。 */
public struct ResolvedBillingPreference: Codable, Sendable, Hashable {
    public var receiptPosition: BillingReceiptPosition = .fallback

    public init() {}
}

/** 收藏联动（加上默认 true，取消默认 false）。 */
public struct ResolvedFavoritePreference: Codable, Sendable, Hashable {
    public var autoOnVenueAction = true
    public var withVenueWhenBuilding = true
    public var withBuildingWhenVenue = true
    public var withoutVenueWhenBuilding = false
    public var withoutBuildingWhenVenue = false

    public init() {}
}

/** 已解析的单个底栏槽：页面 + 图标组。 */
public struct ResolvedAndroidNavSlot: Codable, Sendable, Hashable {
    public var destination: ShellDestination
    public var iconPack: ShellNavIconPack

    public init(_ destination: ShellDestination, iconPack: ShellNavIconPack? = nil) {
        self.destination = destination
        self.iconPack = iconPack ?? destination.defaultIconPack
    }
}

/**
 * 手机底栏偏好（槽 5 固定 Apps 展开，不存字段）。
 * 随 profile.preference.android 上下传（iOS 与 Android 共用），避免网页 sync 冲掉手机底栏配置。
 */
public struct ResolvedAndroidPreference: Codable, Sendable, Hashable {
    public var slot1 = ResolvedAndroidNavSlot(.explore, iconPack: .explore)
    public var slot2 = ResolvedAndroidNavSlot(.search, iconPack: .sports)
    public var slot3 = ResolvedAndroidNavSlot(.venueSearch, iconPack: .place)
    public var slot4 = ResolvedAndroidNavSlot(.chatHub, iconPack: .chat)
    public var slot6 = ResolvedAndroidNavSlot(.create, iconPack: .create)
    /** Loop app 的桌面图标；Near 不读。 */
    public var loopLauncherIcon: LauncherIcon = .fallback
    /** Near app 的桌面图标；Loop 不读。 */
    public var nearLauncherIcon: LauncherIcon = .fallback

    public init() {}

    public static let `default` = ResolvedAndroidPreference()

    /** organization / authority 无活动页：底栏默认换成主页 / 地图 / 球馆 / 消息，槽 6 为设置。 */
    private static let nonCommunityDefault: ResolvedAndroidPreference = {
        var preference = ResolvedAndroidPreference()
        preference.slot1 = ResolvedAndroidNavSlot(.profile)
        preference.slot2 = ResolvedAndroidNavSlot(.explore)
        preference.slot3 = ResolvedAndroidNavSlot(.venueSearch)
        preference.slot4 = ResolvedAndroidNavSlot(.chatHub)
        preference.slot6 = ResolvedAndroidNavSlot(.settings)
        return preference
    }()

    public static func defaultFor(_ kind: ProfileKind) -> ResolvedAndroidPreference {
        kind == .community ? .default : nonCommunityDefault
    }

    /** 槽 1–4（槽 5 是 Apps，槽 6 单独放）。 */
    public var capsuleSlots: [ResolvedAndroidNavSlot] { [slot1, slot2, slot3, slot4] }

    public var occupied: Set<ShellDestination> {
        [slot1.destination, slot2.destination, slot3.destination, slot4.destination, slot6.destination]
    }

    public func appsTrayDestinations(kind: ProfileKind, supported: Set<ShellDestination>) -> [ShellDestination] {
        ShellDestination.available(for: kind, supported: supported).filter { !occupied.contains($0) }
    }

    public func slot(_ index: Int) -> ResolvedAndroidNavSlot {
        switch index {
        case 1: slot1
        case 2: slot2
        case 3: slot3
        case 4: slot4
        case 6: slot6
        default: preconditionFailure("invalid nav slot \(index)")
        }
    }

    public func withSlot(_ index: Int, _ value: ResolvedAndroidNavSlot) -> ResolvedAndroidPreference {
        var next = self
        switch index {
        case 1: next.slot1 = value
        case 2: next.slot2 = value
        case 3: next.slot3 = value
        case 4: next.slot4 = value
        case 6: next.slot6 = value
        default: break
        }
        return next
    }

    /** 规范化：非法/重复/该身份不可用的页回落默认，保证五槽页面互不重复；去重换页时一并换成该页默认图标组。 */
    public func resolved(kind: ProfileKind, supported: Set<ShellDestination>) -> ResolvedAndroidPreference {
        Self.resolve(
            kind: kind,
            supported: supported,
            slots: [slot1, slot2, slot3, slot4, slot6],
            loopLauncherIcon: loopLauncherIcon,
            nearLauncherIcon: nearLauncherIcon
        )
    }

    public static func resolve(
        _ wire: AndroidPreference?,
        kind: ProfileKind,
        supported: Set<ShellDestination>
    ) -> ResolvedAndroidPreference {
        guard let wire else { return defaultFor(kind) }
        let slots = [wire.slot1, wire.slot2, wire.slot3, wire.slot4, wire.slot6].map { slot in
            slot?.destination.map { ResolvedAndroidNavSlot($0, iconPack: slot?.icon) }
        }
        return resolve(
            kind: kind,
            supported: supported,
            slots: slots,
            loopLauncherIcon: wire.loopLauncherIcon,
            nearLauncherIcon: wire.nearLauncherIcon
        )
    }

    private static func resolve(
        kind: ProfileKind,
        supported: Set<ShellDestination>,
        slots: [ResolvedAndroidNavSlot?],
        loopLauncherIcon: LauncherIcon?,
        nearLauncherIcon: LauncherIcon?
    ) -> ResolvedAndroidPreference {
        let base = defaultFor(kind)
        let defaults = [base.slot1, base.slot2, base.slot3, base.slot4, base.slot6]
        let available = ShellDestination.available(for: kind, supported: supported)
        var used = Set<ShellDestination>()
        var fixed = defaults
        for index in defaults.indices {
            let candidate = slots[index] ?? defaults[index]
            if available.contains(candidate.destination), !used.contains(candidate.destination) {
                fixed[index] = candidate
                used.insert(candidate.destination)
            } else {
                let preferred = defaults[index].destination
                let fallback = used.contains(preferred)
                    ? available.first { !used.contains($0) } ?? preferred
                    : preferred
                // 去重换页时必须换默认图标组，否则会出现「第1/第3槽同图标」
                fixed[index] = ResolvedAndroidNavSlot(fallback)
                used.insert(fallback)
            }
        }
        var resolved = ResolvedAndroidPreference()
        resolved.slot1 = fixed[0]
        resolved.slot2 = fixed[1]
        resolved.slot3 = fixed[2]
        resolved.slot4 = fixed[3]
        resolved.slot6 = fixed[4]
        resolved.loopLauncherIcon = loopLauncherIcon ?? .fallback
        resolved.nearLauncherIcon = nearLauncherIcon ?? .fallback
        return resolved
    }

    /**
     * 服务端 android 落地：无整块则保留本地；有槽位但缺某个 app 的桌面图标时保留本地图标，不回落默认。
     */
    public static func mergeServer(
        _ wire: AndroidPreference?,
        parsed: ResolvedAndroidPreference,
        local: ResolvedAndroidPreference
    ) -> ResolvedAndroidPreference {
        guard let wire else { return local }
        var merged = parsed
        if wire.loopLauncherIcon == nil { merged.loopLauncherIcon = local.loopLauncherIcon }
        if wire.nearLauncherIcon == nil { merged.nearLauncherIcon = local.nearLauncherIcon }
        return merged
    }

    fileprivate var wire: AndroidPreference {
        func slot(_ value: ResolvedAndroidNavSlot) -> AndroidNavSlot {
            AndroidNavSlot(destination: value.destination, icon: value.iconPack)
        }
        return AndroidPreference(
            slot1: slot(slot1),
            slot2: slot(slot2),
            slot3: slot(slot3),
            slot4: slot(slot4),
            slot6: slot(slot6),
            loopLauncherIcon: loopLauncherIcon,
            nearLauncherIcon: nearLauncherIcon
        )
    }
}

/** 全量偏好（对应 WEB PreferenceStore state）。 */
public struct ResolvedPreference: Codable, Sendable, Hashable {
    public var language: PulsoLanguage = .fallback
    public var theme: PulsoThemeSettings = .default
    public var map = ResolvedMapPreference()
    public var event = ResolvedEventPreference()
    public var billing = ResolvedBillingPreference()
    public var favorite = ResolvedFavoritePreference()
    public var android: ResolvedAndroidPreference = .default

    public init() {}

    public static let `default` = ResolvedPreference()
}

/* ------------------------------ resolve / clamp ------------------------------ */

extension ResolvedEventPreference {
    /** 事件偏好解析：非法/越界回落默认并 clamp（对应 WEB `resolveEventPreference`）。 */
    public init(_ event: EventPreference?) {
        let maxM = (event?.nearbyRadiusMaxM ?? exploreNearbyRadiusMaxM).clamped(to: EventPreferenceLimits.radiusMaxM)
        let minUpper = min(EventPreferenceLimits.radiusMinM.upperBound, maxM - 1)
        let minM = (event?.nearbyRadiusMinM ?? exploreNearbyRadiusMinM)
            .clamped(to: EventPreferenceLimits.radiusMinM.lowerBound...minUpper)
        self.init()
        hiddenNearModules = event?.hiddenNearModules ?? []
        hiddenLoopModules = event?.hiddenLoopModules ?? []
        nearbyPageSize = (event?.nearbyPageSize ?? exploreNearbyPageSize).clamped(to: EventPreferenceLimits.pageSize)
        nearbyRadiusMinM = minM
        nearbyRadiusMaxM = maxM
    }
}

extension ResolvedFavoritePreference {
    public init(_ raw: FavoritePreference?) {
        self.init()
        autoOnVenueAction = raw?.autoOnVenueAction ?? true
        withVenueWhenBuilding = raw?.withVenueWhenBuilding ?? true
        withBuildingWhenVenue = raw?.withBuildingWhenVenue ?? true
        withoutVenueWhenBuilding = raw?.withoutVenueWhenBuilding ?? false
        withoutBuildingWhenVenue = raw?.withoutBuildingWhenVenue ?? false
    }
}

/** `#rgb` / `#rrggbb`（大小写不限）之外的输入丢弃（对应 WEB `normalizeHexColor`）。 */
public func normalizeHexColor(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespaces),
          value.wholeMatch(of: /#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})/) != nil
    else { return nil }
    return value.lowercased()
}

/** 头像字符归一：取首个非空白字符大写（对应 WEB `normalizeAvatarChar`）。 */
public func normalizeAvatarChar(_ raw: String?) -> String? {
    raw?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
}

/* ------------------------------ server ⇄ resolved ------------------------------ */

extension ResolvedPreference {
    /** 服务端 `Preference` → 本地 Resolved（对应 WEB `parseServerPreference`）。 */
    public init(server pref: Preference?, kind: ProfileKind, supported: Set<ShellDestination>) {
        self.init()
        let theme = pref?.theme
        let map = pref?.map
        language = pref?.language ?? .fallback
        self.theme = PulsoThemeSettings(
            appearance: theme?.appearance ?? .fallback,
            accent: theme?.accent ?? .fallback,
            gray: theme?.gray ?? .fallback,
            radius: theme?.radius ?? .fallback,
            scaling: theme?.scaling ?? .fallback,
            panelBackground: theme?.panelBackground ?? .fallback,
            fontFamily: theme?.fontFamily ?? .fallback
        )
        self.map.mapLightStyle = map?.mapLightStyle ?? .fallback
        self.map.mapDarkStyle = map?.mapDarkStyle ?? .fallback
        self.map.map3d = map?.map3d ?? false
        self.map.mapflat = map?.mapflat ?? true
        self.map.showEventCards = map?.showEventCards
        self.map.showVenueCards = map?.showVenueCards
        self.map.locationRing = normalizeHexColor(map?.locationRing)
        self.map.locationDot = normalizeHexColor(map?.locationDot)
        self.map.locationBorder = normalizeHexColor(map?.locationBorder)
        self.map.locationAvatarUseImage = map?.locationAvatarUseImage
        self.map.locationAvatarBg = normalizeHexColor(map?.locationAvatarBg)
        self.map.locationAvatarBorder = normalizeHexColor(map?.locationAvatarBorder)
        self.map.locationAvatarChar = normalizeAvatarChar(map?.locationAvatarChar)
        event = ResolvedEventPreference(pref?.event)
        billing.receiptPosition = pref?.billing?.receiptPosition ?? .fallback
        favorite = ResolvedFavoritePreference(pref?.favorite)
        android = .resolve(pref?.android, kind: kind, supported: supported)
    }

    /** 本地 Resolved → 上传给服务端的 `Preference`（对应 WEB `toServerPreference`）。 */
    public var serverPreference: Preference {
        Preference(
            theme: ThemePreference(
                accent: theme.accent,
                gray: theme.gray,
                appearance: theme.appearance,
                radius: theme.radius,
                scaling: theme.scaling,
                panelBackground: theme.panelBackground,
                fontFamily: theme.fontFamily
            ),
            language: language,
            map: MapPreference(
                mapLightStyle: map.mapLightStyle,
                mapDarkStyle: map.mapDarkStyle,
                map3d: map.map3d,
                mapflat: map.mapflat,
                showEventCards: map.showEventCards,
                showVenueCards: map.showVenueCards,
                locationRing: map.locationRing,
                locationDot: map.locationDot,
                locationBorder: map.locationBorder,
                locationAvatarUseImage: map.locationAvatarUseImage,
                locationAvatarBg: map.locationAvatarBg,
                locationAvatarBorder: map.locationAvatarBorder,
                locationAvatarChar: map.locationAvatarChar
            ),
            event: EventPreference(
                hiddenNearModules: event.hiddenNearModules.isEmpty ? nil : event.hiddenNearModules,
                hiddenLoopModules: event.hiddenLoopModules.isEmpty ? nil : event.hiddenLoopModules,
                nearbyPageSize: event.nearbyPageSize == exploreNearbyPageSize ? nil : event.nearbyPageSize,
                nearbyRadiusMinM: event.nearbyRadiusMinM == exploreNearbyRadiusMinM ? nil : event.nearbyRadiusMinM,
                nearbyRadiusMaxM: event.nearbyRadiusMaxM == exploreNearbyRadiusMaxM ? nil : event.nearbyRadiusMaxM
            ),
            billing: BillingPreference(receiptPosition: billing.receiptPosition),
            favorite: FavoritePreference(
                autoOnVenueAction: favorite.autoOnVenueAction,
                withVenueWhenBuilding: favorite.withVenueWhenBuilding,
                withBuildingWhenVenue: favorite.withBuildingWhenVenue,
                withoutVenueWhenBuilding: favorite.withoutVenueWhenBuilding,
                withoutBuildingWhenVenue: favorite.withoutBuildingWhenVenue
            ),
            android: android.wire
        )
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
