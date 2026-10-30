import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 地图建筑徽章：按 `building_type` 换图标和颜色（Android `BuildingTypeVisuals`，Radix 浅色 9 / 3 档，WEB `BuildingPin`）。
 * 形状是圆角方块，不是圆点。
 */
struct BuildingTypeVisual {
    let scale: RadixScale
    let systemImage: String

    var accent: Color { scale.lightStep(9) }
    var accentBg: Color { scale.lightStep(3) }

    static func of(_ wire: String?) -> BuildingTypeVisual {
        switch BuildingType.fromWire(wire) {
        case .sportsVenue: BuildingTypeVisual(scale: .orange, systemImage: "building.2")
        case .leisureVenue: BuildingTypeVisual(scale: .amber, systemImage: "square.grid.2x2")
        case .outdoorCourt: BuildingTypeVisual(scale: .cyan, systemImage: "tennis.racket")
        case .park: BuildingTypeVisual(scale: .grass, systemImage: "tree")
        }
    }
}

/** 赛事针和卡片的琥珀色（Android `VenueTone.Amber`）。 */
let tournamentTone = RadixScale.amber.lightStep(9)

/** 地图针的叠放层次（Android `ExploreMapLayer`）：活动 < 球馆 < 我的位置 < 常驻卡片 < 选中针 < 选中卡片。 */
enum ExploreMapLayer {
    static let eventPin: Double = 10
    static let venuePin: Double = 20
    static let myLocation: Double = 30
    static let eventCard: Double = 40
    static let venueCard: Double = 50
    static let selectedPin: Double = 100
    static let selectedCard: Double = 200
}

extension LoopSport {
    /** PNG 的视觉中心（WEB `--icon-x` / `--icon-y`）。 */
    var iconAnchor: CGPoint {
        switch self {
        case .badminton: CGPoint(x: 0.533, y: 0.427)
        case .tennis: CGPoint(x: 0.562, y: 0.492)
        case .football: CGPoint(x: 0.501, y: 0.477)
        case .baseball: CGPoint(x: 0.495, y: 0.531)
        default: CGPoint(x: 0.5, y: 0.5)
        }
    }

    var pinAccent: Color { colorScale.lightStep(9) }
    var pinAccentBg: Color { colorScale.lightStep(3) }
    var pinHeading: Color { colorScale.lightStep(12) }
}

/** 运动图标占圆点 78%，并按 PNG 的视觉中心对正（WEB `.glyph img`）。 */
struct SportPinGlyph: View {
    let sport: LoopSport
    let size: CGFloat

    var body: some View {
        let icon = size * 0.78
        Image(sport.iconAsset)
            .resizable()
            .scaledToFit()
            .frame(width: icon, height: icon)
            .offset(x: icon * (0.5 - sport.iconAnchor.x), y: icon * (0.5 - sport.iconAnchor.y))
            .frame(width: size, height: size)
    }
}

/* ------------------------------ 活动针 ------------------------------ */

/** 活动锚点（Android `ExplorePinFlyer`）：白底描边圆 + 运动图标，外面一圈呼吸光晕。 */
struct ExploreEventPin: View {
    let pin: ExplorePin
    let selected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var sport: LoopSport { LoopSport.fromEventType(pin.eventType) }

    var body: some View {
        let accent = sport.pinAccent
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(accent.opacity(selected ? 0.55 : 0.34))
                    .overlay(Circle().stroke(accent.opacity(selected ? 0.72 : 0.42), lineWidth: 1.5))
                    .scaleEffect(breathing ? 1.28 : 1)
                    .opacity(breathing ? 0.72 : 1)
                Circle()
                    .fill(Color(.systemBackground))
                    .overlay(Circle().stroke(accent, lineWidth: 2))
                    .frame(width: 24, height: 24)
                    .overlay(SportPinGlyph(sport: sport, size: 20))
                    .shadow(color: .black.opacity(0.25), radius: selected ? 6 : 3, y: 1)
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: pin.title.isEmpty ? String(localized: "explore_pin_untitled") : pin.title))
        .onAppear {
            guard !reduceMotion else { return }
            // WEB `pinRingBreath`：半程 1.44 秒放大到 1.28，来回。
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 1.44).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/** 活动卡片（Android `ExplorePinFlyerCard`）：缩略图 + 标题、浏览数 + 运动 · 赛制 · 价格 · 时间。 */
struct ExploreEventPinCard: View {
    let pin: ExplorePin
    let imageURL: URL?
    /** 浮在地图上（固定宽、带阴影）；false 是聚合面板里的一行。 */
    var pinned = false
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    private var sport: LoopSport { LoopSport.fromEventType(pin.eventType) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        sport.pinAccentBg
                        if let imageURL {
                            PulsoRemoteImage(url: imageURL)
                        } else {
                            Image(sport.iconAsset).resizable().scaledToFit().frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 10))
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        .frame(width: 20, height: 20)
                        .overlay(SportPinGlyph(sport: sport, size: 16))
                        .padding(4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: pin.title.isEmpty ? String(localized: "explore_pin_untitled") : pin.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sport.pinHeading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if pin.view > 0 {
                            Label { Text(verbatim: "\(pin.view)") } icon: { Image(systemName: "eye") }
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .foregroundStyle(sport.pinAccent)
                                .accessibilityLabel(Text("shell_event_list_views_label"))
                        }
                    }
                    Text(verbatim: summary)
                        .font(.caption2)
                        .foregroundStyle(sport.pinAccent)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(width: pinned ? 168 : nil)
            .frame(maxWidth: pinned ? nil : 280)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .shadow(color: .black.opacity(pinned ? 0.2 : 0), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        let price = pin.isFree ? String(localized: "explore_pin_free") : pin.priceAmount.map { formatMoney($0, currency: pin.currency, locale: locale) } ?? "—"
        return [
            String(localized: sport.labelResource),
            String(localized: pin.matchFormat.labelResource),
            price,
            DateTimeFormatters.sessionDayClockRange(pin.startsAt, pin.endsAt, locale: locale),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

/* ------------------------------ 球馆 / 建筑 / 赛事针 ------------------------------ */

/** 球馆锚点（Android `ExploreVenuePin`）：圆角方块，图标和颜色跟建筑类型；右上角今天空着的场地数。 */
struct ExploreVenuePin: View {
    let pin: NearbyVenuePin
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let visual = BuildingTypeVisual.of(pin.building.type)
        Button(action: onTap) {
            Image(systemName: visual.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.white : visual.accent)
                .frame(width: 30, height: 30)
                .background(selected ? visual.accent : visual.accentBg, in: .rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(visual.accent, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: selected ? 6 : 3, y: 1)
                .overlay(alignment: .topTrailing) {
                    if pin.freeCourtsToday > 0 {
                        Text(verbatim: "\(pin.freeCourtsToday)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.accentColor, in: .capsule)
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: venuePinSummary(pin)))
    }
}

/** 没有 Loop 球馆的 PulsoLink 建筑（Android `ExploreBuildingPin`）：圆角方块，图标和颜色跟建筑类型。 */
struct ExploreBuildingPin: View {
    let building: BuildingItem
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let visual = BuildingTypeVisual.of(building.buildingType)
        Button(action: onTap) {
            Image(systemName: visual.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.white : visual.accent)
                .frame(width: 28, height: 28)
                .background(selected ? visual.accent : visual.accentBg, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(visual.accent, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: selected ? 6 : 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: building.name))
    }
}

/** 赛事在某家参赛球馆的点（Android `ExploreTournamentPin`）：琥珀色奖杯圆标。 */
struct ExploreTournamentPin: View {
    let pin: TournamentPin
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color(.systemBackground) : tournamentTone)
                .frame(width: 30, height: 30)
                .background(selected ? tournamentTone : tournamentTone.opacity(0.18), in: .circle)
                .overlay(Circle().stroke(tournamentTone, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: selected ? 6 : 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: pin.title))
    }
}

/** 选中球馆的卡片（Android `ExploreVenuePinCard`，WEB `VenuePinCard`）：封面铺底、文字压在渐变上，右上角是开设的运动。 */
struct ExploreVenuePinCard: View {
    let pin: NearbyVenuePin
    let imageURL: URL?
    var pinned = false
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let imageURL { PulsoRemoteImage(url: imageURL) }
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.2), .init(color: .black.opacity(0.35), location: 0.55), .init(color: .black.opacity(0.78), location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pin.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(verbatim: freeTodayLabel(pin))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(pin.freeCourtsToday > 0 ? Color.accentColor : Color.white.opacity(0.22), in: .capsule)
                        Text(verbatim: meta)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .frame(width: pinned ? 168 : nil, height: pinned ? 96 : 132)
            .frame(maxWidth: pinned ? nil : 280)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: 1.5))
            .shadow(color: .black.opacity(pinned ? 0.2 : 0), radius: 8, y: 2)
            .overlay(alignment: .topTrailing) {
                // 每项运动一个圆标，一排骑在卡片右上角（一半在外，WEB `SportBadge`）。
                HStack(spacing: 4) {
                    ForEach(pin.sports, id: \.self) { sport in
                        Image(sport.loopSport.iconAsset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 19, height: 19)
                            .frame(width: 26, height: 26)
                            .background(Color(.secondarySystemGroupedBackground), in: .circle)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .accessibilityLabel(Text(sport.loopSport.labelKey))
                    }
                }
                .offset(x: 10, y: -13)
            }
        }
        .buttonStyle(.plain)
    }

    private var meta: String {
        [
            distanceLabel(pin.distanceM),
            venuePriceLabel(pin, locale: locale),
            pin.view > 0 ? localizedFormat("shell_views_count", pin.view) : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/** 选中赛事点后的卡片（Android `ExploreTournamentPinCard`）；点进赛事详情。 */
struct ExploreTournamentPinCard: View {
    let pin: TournamentPin
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pin.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                (Text(pin.status.labelKey) + Text(verbatim: " · " + (DateTimeFormatters.monthDayTime(pin.startsAt, locale: locale) ?? "")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: pin.venueCount > 1 ? localizedFormat("tournament_pin_more_venues", pin.venueName, pin.venueCount - 1) : pin.venueName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tournamentTone, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/* ------------------------------ 我的位置 ------------------------------ */

/** 我的位置（Android `ExploreMyLocationPin`，WEB MyLocation）：环 + 点 + 头像或首字母徽章，颜色来自偏好，缺省主色。 */
struct ExploreMyLocationPin: View {
    let map: ResolvedMapPreference
    let displayName: String?
    let avatarURL: URL?
    let onTap: () -> Void

    var body: some View {
        let ring = preferenceColor(map.locationRing) ?? .accentColor
        let dot = preferenceColor(map.locationDot) ?? .accentColor
        let border = preferenceColor(map.locationBorder) ?? Color(.systemBackground)
        let badgeBg = preferenceColor(map.locationAvatarBg) ?? .accentColor
        let badgeBorder = preferenceColor(map.locationAvatarBorder) ?? Color(.systemBackground)
        Button(action: onTap) {
            ZStack {
                Circle().fill(ring.opacity(0.28)).overlay(Circle().stroke(ring.opacity(0.5), lineWidth: 1.5))
                Circle().fill(dot).overlay(Circle().stroke(border, lineWidth: 1.5)).frame(width: 14, height: 14)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(badgeBg)
                    if map.locationAvatarUseImage != false, let avatarURL {
                        PulsoRemoteImage(url: avatarURL).clipShape(.circle)
                    } else {
                        Text(verbatim: initial).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(badgeBorder, lineWidth: 1.5))
                .offset(x: 4, y: -4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: displayName ?? ""))
    }

    private var initial: String {
        if let char = map.locationAvatarChar?.trimmingCharacters(in: .whitespaces), !char.isEmpty { return char }
        return displayName?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/** 偏好里的 `#RRGGBB` / `#AARRGGBB`；读不了时 nil（用缺省色）。 */
func preferenceColor(_ hex: String?) -> Color? {
    guard var raw = hex?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    if raw.hasPrefix("#") { raw.removeFirst() }
    guard raw.count == 6 || raw.count == 8, let value = UInt64(raw, radix: 16) else { return nil }
    let argb = raw.count == 6 ? 0xFF00_0000 | value : value
    return Color(
        .sRGB,
        red: Double((argb >> 16) & 0xFF) / 255,
        green: Double((argb >> 8) & 0xFF) / 255,
        blue: Double(argb & 0xFF) / 255,
        opacity: Double((argb >> 24) & 0xFF) / 255
    )
}

/* ------------------------------ 文案 ------------------------------ */

func freeTodayLabel(_ pin: NearbyVenuePin) -> String {
    pin.freeCourtsToday > 0 ? localizedFormat("map_venue_pin_free_today", pin.freeCourtsToday) : String(localized: "map_venue_pin_full_today")
}

func venuePriceLabel(_ pin: NearbyVenuePin, locale: Locale) -> String? {
    pin.sportEntries.lowestHourlyPrice.map { localizedFormat("map_venue_pin_from_price", formatMoney($0, currency: pin.currency, locale: locale)) }
}

private func venuePinSummary(_ pin: NearbyVenuePin) -> String {
    [pin.displayName, distanceLabel(pin.distanceM), freeTodayLabel(pin), venuePriceLabel(pin, locale: .current)]
        .compactMap { $0 }
        .joined(separator: " · ")
}

extension VenueAmenityPreset {
    /** 设施图标 → SF Symbol。 */
    var systemImage: String {
        switch self {
        case .parking: "car"
        case .showers: "shower"
        case .lockers: "lock"
        case .racketRental: "dollarsign.circle"
        case .proShop: "cart"
        case .wheelchairAccess: "figure.roll"
        }
    }
}
