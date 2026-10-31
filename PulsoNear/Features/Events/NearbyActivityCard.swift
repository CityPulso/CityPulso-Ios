import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 附近活动卡片（对应 Android `NearbyActivityCard`）：方形封面，标题 / 时间 / 地点 · 距离 / 活动类型标签，
 * 名额、价格和实心「查看」。长按菜单里「在地图上看」。
 */
struct NearbyActivityCard: View {
    let pin: ExplorePin
    let imageURL: URL?
    let origin: PickedLocation?

    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette

    private var activityType: NearActivityKind { NearActivityKind.fromActivityType(pin.activityType) }

    private var place: String {
        let distance: String? = if let origin, let lat = pin.locationLat, let lng = pin.locationLng {
            distanceLabel(haversineM(origin.latitude, origin.longitude, lat, lng))
        } else {
            nil
        }
        return [pin.venueName ?? pin.address, distance].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s3) {
            HStack(alignment: .top, spacing: PulsoSpace.s3) {
                ActivityTypeCover(url: imageURL, activityType: activityType)
                    .frame(width: 96, height: 96)
                    .clipShape(palette.innerShape)
                VStack(alignment: .leading, spacing: PulsoSpace.s1) {
                    Group {
                        if pin.title.isEmpty { Text("explore_pin_untitled") } else { Text(verbatim: pin.title) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    meta("calendar", DateTimeFormatters.sessionDayClockRange(pin.startsAt, pin.endsAt, locale: locale))
                    if !place.isEmpty { meta("mappin.and.ellipse", place) }
                    HStack(spacing: 4) {
                        tag(Text(activityType.labelKey), foreground: activityType.colorScale.step(11), background: activityType.colorScale.step(3))
                    }
                }
            }
            HStack(spacing: PulsoSpace.s4) {
                if pin.capacity > 0 {
                    Label {
                        Text(verbatim: localizedFormat("nearby_activity_seats", pin.seatsTaken, pin.capacity))
                    } icon: {
                        Image(systemName: "person.3")
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.text)
                }
                Group {
                    if pin.isFree || pin.priceAmount == nil {
                        Text("nearby_filter_price_free")
                    } else {
                        Text(verbatim: formatMoney(pin.priceAmount ?? 0, currency: pin.currency, locale: locale))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.text)
                Spacer()
                // 整张卡片可点；这里画成实心按钮的样子（Android 「查看」PulsoButton）。
                Text("nearby_activity_view")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, PulsoSpace.s5)
                    .frame(height: PulsoControlSize.compact.height)
                    .background(palette.accent.step(9), in: palette.controlShape)
            }
        }
    }

    private func meta(_ systemImage: String, _ text: String) -> some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: systemImage) }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
    }

    private func tag(_ text: Text, foreground: some ShapeStyle, background: some ShapeStyle) -> some View {
        text
            .font(.caption2.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, PulsoSpace.s2)
            .padding(.vertical, PulsoSpace.half)
            .background(background, in: palette.chipShape)
    }
}
