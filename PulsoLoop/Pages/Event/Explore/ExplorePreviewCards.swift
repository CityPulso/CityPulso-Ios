import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 选了运动时，选中活动或球馆的预览卡，从底部滑上来（Android `ExplorePreviewCards`）。 */
struct ExplorePreviewCards: View {
    let model: ExploreModel
    let onOpenEvent: (ExplorePin) -> Void
    let onRoute: (LoopRoute) -> Void

    var body: some View {
        if let event = model.previewEvent {
            ExploreEventPreviewCard(
                pin: event,
                preview: model.eventPreview.data,
                imageURL: { model.imageURL($0) },
                distanceM: model.distanceToM(event.locationLat, event.locationLng),
                onClose: { model.clearSelection() },
                onDetails: { onOpenEvent(event) },
                onJoin: { onRoute(.joinEvent(sport: LoopSport.fromEventType(event.eventType), eventId: event.id)) }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let venue = model.previewVenue {
            let ids = model.venuePreviewImageIds.isEmpty ? [venue.coverImageId].compactMap { $0 } : model.venuePreviewImageIds
            ExploreVenuePreviewCard(
                pin: venue,
                imageURLs: ids.compactMap { model.imageURL($0) },
                onClose: { model.clearSelection() },
                onBook: {
                    if let route = model.bookRoute(venue) { onRoute(route) }
                },
                onDetails: { onRoute(.venue(venueId: venue.id)) }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/** 活动预览卡（Android `ExploreEventPreviewCard`）：照片上压着时间，标题、地点和距离、运动和人数、两行简介，然后「看详情」「报名」。 */
private struct ExploreEventPreviewCard: View {
    let pin: ExplorePin
    let preview: ExploreEventPreview?
    let imageURL: (String?) -> URL?
    let distanceM: Double?
    let onClose: () -> Void
    let onDetails: () -> Void
    let onJoin: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let sport = LoopSport.fromEventType(pin.eventType)
        let ids = (preview?.imageIds).flatMap { $0.isEmpty ? nil : $0 } ?? [pin.imageId].compactMap { $0 }
        PreviewShell(
            imageURLs: ids.compactMap(imageURL),
            sport: sport,
            badge: DateTimeFormatters.sessionDayClockRange(pin.startsAt, pin.endsAt, locale: locale),
            onClose: onClose
        ) {
            Text(verbatim: pin.title.isEmpty ? String(localized: "explore_pin_untitled") : pin.title)
                .font(.title3.bold())
                .lineLimit(2)
            MetaLine(systemImage: "mappin.and.ellipse", text: [pin.venueName ?? pin.address, distanceM.map(distanceLabel)].compactMap { $0 }.joined(separator: " · "))
            HStack(spacing: 6) {
                SportTag(sport: sport)
                if let preview, preview.capacity > 0 {
                    Label { Text(verbatim: localizedFormat("explore_preview_spots", preview.participating, preview.capacity)) } icon: { Image(systemName: "person.2") }
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }
            if let description = preview?.description, !description.isEmpty {
                Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            VStack(spacing: 8) {
                Button(action: onDetails) { Text("explore_preview_event_details").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
                if !pin.isEnded {
                    Button(action: onJoin) { Text("explore_preview_join").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
    }
}

/** 球馆预览卡（Android `ExploreVenuePreviewCard`）：照片、名字、距离、运动、现在开没开，然后「订场」「看球馆」。 */
private struct ExploreVenuePreviewCard: View {
    let pin: NearbyVenuePin
    let imageURLs: [URL]
    let onClose: () -> Void
    let onBook: () -> Void
    let onDetails: () -> Void

    var body: some View {
        PreviewShell(imageURLs: imageURLs, sport: pin.sports.first?.loopSport ?? .badminton, badge: nil, onClose: onClose) {
            Text(verbatim: pin.displayName).font(.title3.bold()).lineLimit(2)
            MetaLine(systemImage: "mappin.and.ellipse", text: [pin.displayAddress.isEmpty ? nil : pin.displayAddress, distanceLabel(pin.distanceM)].compactMap { $0 }.joined(separator: " · "))
            if !pin.sports.isEmpty {
                PulsoFlowLayout(spacing: 6) {
                    ForEach(pin.sports, id: \.self) { SportTag(sport: $0.loopSport) }
                }
            }
            if let status = venueOpenStatus(venueWeek(pin.hours), timezone: pin.timezone) {
                VenueOpenChip(status: status)
            }
            VStack(spacing: 8) {
                if !pin.sports.isEmpty {
                    Button(action: onBook) { Text("explore_preview_book").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                }
                Button(action: onDetails) { Text("explore_preview_venue_details").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
    }
}

/** 卡片外框：可左右滑的照片和页点（没有照片时显示运动图标）、关闭按钮和可选的角标，下面是 [content]。 */
private struct PreviewShell<Content: View>: View {
    let imageURLs: [URL]
    let sport: LoopSport
    let badge: String?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if imageURLs.isEmpty {
                    SportCover(url: nil, sport: sport, iconSize: 64)
                } else {
                    TabView(selection: $page) {
                        ForEach(imageURLs.indices, id: \.self) { index in
                            PulsoRemoteImage(url: imageURLs[index]).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: imageURLs.count > 1 ? .always : .never))
                }
            }
            .frame(height: 168)
            .clipped()
            .overlay(alignment: .topLeading) {
                if let badge, !badge.isEmpty {
                    Label { Text(verbatim: badge) } icon: { Image(systemName: "calendar") }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: .capsule)
                        .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.footnote.bold()).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(8)
                .accessibilityLabel(Text("explore_preview_close"))
            }
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

private struct MetaLine: View {
    let systemImage: String
    let text: String

    var body: some View {
        if !text.isEmpty {
            Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: systemImage) }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/** 运动标签，用运动自己的颜色（和地图针一样）。 */
struct SportTag: View {
    let sport: LoopSport

    var body: some View {
        HStack(spacing: 4) {
            Image(sport.iconAsset).resizable().scaledToFit().frame(width: 16, height: 16)
            Text(sport.labelKey).font(.subheadline).foregroundStyle(sport.pinHeading)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(sport.pinAccentBg, in: .capsule)
        .overlay(Capsule().stroke(sport.pinAccent.opacity(0.4), lineWidth: 0.5))
    }
}

/** 营业中 · 几点打烊 / 已打烊 · 什么时候开门（Android `VenueOpenChip`）。 */
struct VenueOpenChip: View {
    let status: VenueOpenStatus

    @Environment(\.locale) private var locale

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case let .open(closesAt): (localizedFormat("venue_detail_open_until", closesAt), RadixScale.green.lightStep(9))
        case let .closed(opensAt, inDays, dayOfWeek):
            (closedText(opensAt: opensAt, inDays: inDays, dayOfWeek: dayOfWeek), RadixScale.slate.lightStep(9))
        }
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: .capsule)
    }

    private func closedText(opensAt: String, inDays: Int, dayOfWeek: Int) -> String {
        switch inDays {
        case 0: return localizedFormat("venue_detail_opens_today", opensAt)
        case 1: return localizedFormat("venue_detail_opens_tomorrow", opensAt)
        default:
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            // ISO 周一 = 1 → Calendar 的 weekdaySymbols（周日在前）。
            let name = calendar.standaloneWeekdaySymbols[dayOfWeek % 7]
            return localizedFormat("venue_detail_opens_on", name, opensAt)
        }
    }
}
