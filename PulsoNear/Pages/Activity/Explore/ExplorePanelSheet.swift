import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 面板里的两个列表。 */
private enum ExploreSheetTab: Hashable, CaseIterable {
    case activities
    case venues
}

/** 卡片区显示的那一张。 */
private enum ExplorePeek {
    case activity(ExplorePin)
    case venue(NearbyVenuePin)
    case building(BuildingItem)
    case empty
}

extension ExploreModel {
    /** 点了什么显示什么；建筑上有门店显示门店，没有就显示建筑；都没选显示离我最近的一条。 */
    fileprivate var peek: ExplorePeek {
        if let pin = pins.first(where: { $0.id == selectedPinId }) { return .activity(pin) }
        if let pin = venuePins.first(where: { $0.id == selectedVenueId }) { return .venue(pin) }
        if let building = buildingPins.first(where: { $0.id == selectedBuildingId }) {
            if let venue = venuePins.first(where: { $0.building.id == building.id }) { return .venue(venue) }
            return .building(building)
        }
        if let pin = sortedActivities.first { return .activity(pin) }
        if let pin = sortedVenues.first { return .venue(pin) }
        return .empty
    }
}

/**
 * Explore 的底部面板（Android `ExploreBottomSheet`）：点了针弹到「卡片」高度显示一张卡；上拉到全屏是
 * 「活动 / 门店」两个附近列表；拉下去就收起并清掉选中，再点同一个针还会弹出来。地图在卡片高度以下仍可操作。
 */
struct ExplorePanelSheet: View {
    let model: ExploreModel
    let onOpenActivity: (ExplorePin) -> Void
    let onRoute: (NearRoute) -> Void

    @State private var tab = ExploreSheetTab.activities
    @State private var peekHeight: CGFloat = 180
    @State private var detent = PresentationDetent.height(180)

    var body: some View {
        VStack(spacing: 0) {
            peekCard
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    let wasPeek = detent == .height(peekHeight)
                    peekHeight = height
                    if wasPeek { detent = .height(height) }
                }
            if detent == .large {
                Picker(selection: $tab) {
                    Text("explore_sheet_tab_activities").tag(ExploreSheetTab.activities)
                    Text("explore_sheet_tab_venues").tag(ExploreSheetTab.venues)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                nearbyList
            }
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(peekHeight), .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(peekHeight)))
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        // 点了另一个针：不管面板在哪，回到卡片高度让卡露出来。
        .onChange(of: [model.selectedPinId, model.selectedVenueId, model.selectedBuildingId]) {
            detent = .height(peekHeight)
        }
    }

    @ViewBuilder
    private var peekCard: some View {
        switch model.peek {
        case let .activity(pin):
            // 点中的针预览已经加载了详情，第一张照片比列表摘要（常常没有图）好。
            let imageId = pin.id == model.selectedPinId ? (model.activityPreview.data?.imageIds.first ?? pin.imageId) : pin.imageId
            ExploreActivitySheetCard(pin: pin, imageURL: model.imageURL(imageId), distanceM: model.distanceToM(pin.locationLat, pin.locationLng), thumbSize: 88) {
                onOpenActivity(pin)
            }
        case let .venue(pin):
            let imageId = pin.id == model.selectedVenueId ? (model.venuePreviewImageIds.first ?? pin.coverImageId) : pin.coverImageId
            ExploreVenueSheetCard(pin: pin, imageURL: model.imageURL(imageId), distanceM: model.distanceToM(pin.pinLat, pin.pinLng)) {
                onRoute(.venue(venueId: pin.id))
            }
        case let .building(building):
            ExploreBuildingSheetCard(building: building, imageURL: model.imageURL(building.coverImageId), distanceM: model.distanceToM(building.locationLat, building.locationLng)) {
                onRoute(.building(buildingId: building.id))
            }
        case .empty:
            Text("explore_sheet_empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var nearbyList: some View {
        let activities = tab == .activities ? model.sortedActivities : []
        let venues = tab == .venues ? model.sortedVenues : []
        if (tab == .activities && activities.isEmpty) || (tab == .venues && venues.isEmpty) {
            ContentUnavailableView {
                Text((tab == .activities ? "explore_sheet_empty_activities" : "explore_sheet_empty_venues") as LocalizedStringKey)
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(activities, id: \.id) { pin in
                    ExploreActivitySheetCard(pin: pin, imageURL: model.imageURL(pin.imageId), distanceM: model.distanceFromAnchorM(pin.locationLat, pin.locationLng), thumbSize: 64) {
                        model.selectPin(pin.id)
                        onOpenActivity(pin)
                    }
                }
                if tab == .activities, model.showPager {
                    ExplorePagerBar(model: model).frame(maxWidth: .infinity)
                }
                ForEach(venues, id: \.id) { pin in
                    ExploreVenueSheetCard(pin: pin, imageURL: model.imageURL(pin.coverImageId), distanceM: model.distanceFromAnchorM(pin.pinLat, pin.pinLng)) {
                        model.selectVenue(pin.id)
                        onRoute(.venue(venueId: pin.id))
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

/** 上一页 / 页码 / 下一页（Android `ExplorePagerBar`）。 */
private struct ExplorePagerBar: View {
    let model: ExploreModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.goPrevPage() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoPrev || model.isLoading)
                .accessibilityLabel(Text("explore_pager_prev"))
            Text(verbatim: localizedFormat("explore_pager_page", model.pageIndex + 1, model.pageCount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Button { model.goNextPage() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoNext || model.isLoading)
                .accessibilityLabel(Text("explore_pager_next"))
        }
        .buttonStyle(.borderless)
    }
}

/* ------------------------------ 卡片 ------------------------------ */

/** 左图右字：标签 + 距离 / 标题 / 活动类型 / 几行图标说明（Android `ExploreSheetCardFrame`）。 */
private struct ExploreActivitySheetCard: View {
    let pin: ExplorePin
    let imageURL: URL?
    let distanceM: Double?
    let thumbSize: CGFloat
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let activityType = NearActivityKind.fromActivityType(pin.activityType)
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    activityType.pinAccentBg
                    if let imageURL {
                        PulsoRemoteImage(url: imageURL)
                    } else {
                        Image(activityType.iconAsset).resizable().scaledToFit().frame(width: thumbSize / 2, height: thumbSize / 2)
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    SheetTagRow(tag: "explore_sheet_tag_activity", distanceM: distanceM)
                    Text(verbatim: pin.title.isEmpty ? String(localized: "explore_pin_untitled") : pin.title)
                        .font(.headline)
                        .lineLimit(2)
                    ActivityTypeTag(activityType: activityType)
                    let time = DateTimeFormatters.sessionDayClockRange(pin.startsAt, pin.endsAt, locale: locale)
                    if !time.isEmpty { SheetMetaLine(systemImage: "clock", text: time) }
                    if let place = pin.venueName ?? pin.address, !place.isEmpty { SheetMetaLine(systemImage: "mappin.and.ellipse", text: place) }
                    SheetMetaLine(systemImage: "eye", text: localizedFormat("shell_views_count", pin.view))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/** 面板里的门店行（WEB `NearbyVenueList`）：横版封面、营业状态、各活动类型标签、地址和浏览数。 */
private struct ExploreVenueSheetCard: View {
    let pin: NearbyVenuePin
    let imageURL: URL?
    let distanceM: Double?
    let onTap: () -> Void

    var body: some View {
        let activityType = pin.activityTypes.first?.kind ?? .boardGame
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    activityType.pinAccentBg
                    if let imageURL {
                        PulsoRemoteImage(url: imageURL)
                    } else {
                        Image(activityType.iconAsset).resizable().scaledToFit().frame(width: 36, height: 36)
                    }
                }
                .frame(width: 112)
                .frame(minHeight: 72, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    SheetTagRow(tag: "explore_sheet_tag_venue", distanceM: distanceM ?? pin.distanceM)
                    Text(verbatim: pin.displayName.isEmpty ? String(localized: "explore_pin_untitled") : pin.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    if let status = venueOpenStatus(venueWeek(pin.hours), timezone: pin.timezone) {
                        VenueOpenChip(status: status)
                    }
                    if !pin.activityTypes.isEmpty {
                        PulsoFlowLayout(spacing: 4) {
                            ForEach(pin.activityTypes, id: \.self) { ActivityTypeTag(activityType: $0.kind) }
                        }
                    }
                    if !pin.displayAddress.isEmpty { SheetMetaLine(systemImage: "mappin.and.ellipse", text: pin.displayAddress) }
                    SheetMetaLine(systemImage: "eye", text: localizedFormat("shell_views_count", pin.view))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            FavoriteHeart(target: .venue, id: pin.id, name: pin.displayName).padding(.top, 24)
        }
    }
}

private struct ExploreBuildingSheetCard: View {
    let building: BuildingItem
    let imageURL: URL?
    let distanceM: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Color(.tertiarySystemFill)
                    // 建筑的第一张外观照；没有才用图标。
                    if let imageURL {
                        PulsoRemoteImage(url: imageURL)
                    } else {
                        Image(systemName: "building.2").font(.title).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    SheetTagRow(tag: "explore_sheet_tag_building", distanceM: distanceM)
                    Text(verbatim: building.name).font(.headline).lineLimit(2)
                    if !building.address.isEmpty { SheetMetaLine(systemImage: "mappin.and.ellipse", text: building.address) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SheetTagRow: View {
    let tag: LocalizedStringKey
    let distanceM: Double?

    var body: some View {
        HStack {
            Text(tag)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 6))
            Spacer()
            if let distanceM {
                Text(verbatim: distanceLabel(distanceM)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SheetMetaLine: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: systemImage) }
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
