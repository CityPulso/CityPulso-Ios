import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 附近活动卡片（对应 Android `NearbyEventCard`）：方形封面，标题 / 时间 / 地点 · 距离 / 运动和赛制标签，
 * 名额和价格。左滑「在地图上看」用系统的 swipe action。
 */
struct NearbyEventCard: View {
    let pin: ExplorePin
    let imageURL: URL?
    let origin: PickedLocation?

    @Environment(\.locale) private var locale

    private var sport: LoopSport { LoopSport.fromEventType(pin.eventType) }

    private var place: String {
        let distance: String? = if let origin, let lat = pin.locationLat, let lng = pin.locationLng {
            distanceLabel(haversineM(origin.latitude, origin.longitude, lat, lng))
        } else {
            nil
        }
        return [pin.venueName ?? pin.address, distance].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SportCover(url: imageURL, sport: sport)
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if pin.title.isEmpty { Text("explore_pin_untitled") } else { Text(verbatim: pin.title) }
                    }
                    .font(.headline)
                    .lineLimit(2)
                    meta("calendar", DateTimeFormatters.sessionDayClockRange(pin.startsAt, pin.endsAt, locale: locale))
                    if !place.isEmpty { meta("mappin.and.ellipse", place) }
                    HStack(spacing: 4) {
                        tag(Text(sport.labelKey), foreground: sport.colorScale.step(11), background: sport.colorScale.step(3))
                        tag(Text(pin.matchFormat.labelKey), foreground: .secondary, background: Color(.tertiarySystemFill))
                    }
                }
            }
            HStack(spacing: 16) {
                if pin.capacity > 0 {
                    Label {
                        Text(verbatim: localizedFormat("nearby_event_seats", pin.seatsTaken, pin.capacity))
                    } icon: {
                        Image(systemName: "person.2")
                    }
                    .font(.subheadline)
                }
                Group {
                    if pin.isFree || pin.priceAmount == nil {
                        Text("nearby_filter_price_free")
                    } else {
                        Text(verbatim: formatMoney(pin.priceAmount ?? 0, currency: pin.currency, locale: locale))
                    }
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text("nearby_event_view")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }

    private func meta(_ systemImage: String, _ text: String) -> some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: systemImage) }
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func tag(_ text: Text, foreground: some ShapeStyle, background: some ShapeStyle) -> some View {
        text
            .font(.caption2.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
    }
}
