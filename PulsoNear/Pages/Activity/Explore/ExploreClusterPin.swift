import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 屏幕上重叠的针合成一个玻璃聚合针：最多三个类型圆标叠在一起 + 数量角标（Android `ExploreClusterPin`，WEB `PinCluster`）。
 * 点开是一个弹出面板：分段「全部 / 门店 / 活动」，每个针一行（地图开着卡片时显示成卡片），选一行等于点那个针。
 */
struct ExploreClusterPin: View {
    let cluster: ExploreMapCluster
    @Binding var open: Bool
    let activityCards: Bool
    let venueCards: Bool
    let imageURL: (String?) -> URL?
    let onSelect: (ExploreMapItem) -> Void

    var body: some View {
        Button { open = true } label: {
            ClusterStack(items: cluster.items)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay(alignment: .topTrailing) {
                    Text(verbatim: "\(cluster.items.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.accentColor, in: .capsule)
                        .overlay(Capsule().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 5, y: -5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: localizedFormat("explore_cluster_title", cluster.items.count)))
        .popover(isPresented: $open) {
            ClusterPanel(cluster: cluster, activityCards: activityCards, venueCards: venueCards, imageURL: imageURL, onClose: { open = false }, onSelect: onSelect)
                .frame(width: 300)
                .frame(maxHeight: 400)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ClusterPanel: View {
    let cluster: ExploreMapCluster
    let activityCards: Bool
    let venueCards: Bool
    let imageURL: (String?) -> URL?
    let onClose: () -> Void
    let onSelect: (ExploreMapItem) -> Void

    @State private var tab = ExploreClusterTab.all

    var body: some View {
        let tabs = ExploreClusterTab.allCases.filter { $0 == .all || count($0) > 0 }
        let active = tabs.contains(tab) ? tab : .all
        let visible = active == .all ? cluster.items : cluster.items.filter { $0.kind.clusterTab == active }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClusterStack(items: cluster.items).frame(width: 28, height: 26)
                Text(verbatim: localizedFormat("explore_cluster_title", cluster.items.count))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) { Image(systemName: "xmark").font(.footnote.bold()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("explore_cluster_close"))
            }
            if tabs.count > 2 {
                Picker(selection: $tab) {
                    ForEach(tabs, id: \.self) { value in
                        Text(verbatim: "\(String(localized: value.labelResource)) \(count(value))").tag(value)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(visible) { item in
                        ClusterItem(item: item, activityCards: activityCards, venueCards: venueCards, imageURL: imageURL) { onSelect(item) }
                    }
                }
            }
        }
        .padding(12)
    }

    private func count(_ value: ExploreClusterTab) -> Int {
        value == .all ? cluster.items.count : cluster.items.filter { $0.kind.clusterTab == value }.count
    }
}

/** 每个针按地图上的样子显示：开着卡片时是卡片，否则一行（圆标、名字、详情）。 */
private struct ClusterItem: View {
    let item: ExploreMapItem
    let activityCards: Bool
    let venueCards: Bool
    let imageURL: (String?) -> URL?
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        switch item {
        case let .activity(pin) where activityCards:
            ExploreActivityPinCard(pin: pin, imageURL: imageURL(pin.imageId), onTap: onTap)
        case let .venue(pin) where venueCards:
            ExploreVenuePinCard(pin: pin, imageURL: imageURL(pin.coverImageId), onTap: onTap)
        default:
            Button(action: onTap) {
                HStack(spacing: 8) {
                    MarkDisc(mark: ItemMark(item), size: 32, iconSize: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title).font(.subheadline.weight(.medium)).lineLimit(1)
                        if !meta.isEmpty {
                            Text(verbatim: meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.72), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ItemMark(item).ring.opacity(0.5), lineWidth: 0.5))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var title: String {
        switch item {
        case let .activity(pin): pin.title
        case let .venue(pin): pin.displayName
        case let .building(building): building.name
        }
    }

    private var meta: String {
        switch item {
        case let .activity(pin):
            [String(localized: NearActivityKind.fromActivityType(pin.activityType).labelResource), DateTimeFormatters.sessionDayClockRange(pin.startsAt, pin.endsAt, locale: locale)].joined(separator: " · ")
        case let .venue(pin):
            [distanceLabel(pin.distanceM), pin.building.address].filter { !$0.isEmpty }.joined(separator: " · ")
        case let .building(building):
            building.address
        }
    }
}

/** 一个针的圆标：图标、底色和描边色（Android `ItemMark`）。 */
private struct ItemMark {
    let image: Image
    let tint: Color?
    let background: Color
    let ring: Color

    init(_ item: ExploreMapItem) {
        switch item {
        case let .activity(pin):
            let activityType = NearActivityKind.fromActivityType(pin.activityType)
            image = Image(activityType.iconAsset)
            tint = nil
            background = activityType.pinAccentBg
            ring = activityType.pinAccent
        case let .venue(pin):
            let visual = BuildingTypeVisual.of(pin.building.type)
            image = Image(systemName: visual.systemImage)
            tint = visual.accent
            background = visual.accentBg
            ring = visual.accent
        case let .building(building):
            let visual = BuildingTypeVisual.of(building.buildingType)
            image = Image(systemName: visual.systemImage)
            tint = visual.accent
            background = visual.accentBg
            ring = visual.accent
        }
    }
}

private struct MarkDisc: View {
    let mark: ItemMark
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(mark.background)
            if let tint = mark.tint {
                mark.image.resizable().scaledToFit().foregroundStyle(tint).frame(width: iconSize, height: iconSize)
            } else {
                mark.image.resizable().scaledToFit().frame(width: iconSize, height: iconSize)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(mark.ring, lineWidth: 2))
    }
}

/** 最多三个类型圆标叠在一起，看起来像一叠针。 */
private struct ClusterStack: View {
    let items: [ExploreMapItem]

    /** 每种类型一个，按出现顺序。 */
    private var marks: [ExploreMapItem] {
        var seen = Set<ExploreMapItemKind>()
        return Array(items.filter { seen.insert($0.kind).inserted }.prefix(3))
    }

    var body: some View {
        let marks = marks
        ZStack {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, item in
                MarkDisc(mark: ItemMark(item), size: 18, iconSize: 11)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(index, of: marks.count))
            }
        }
        .frame(width: 28, height: 26)
    }

    private func alignment(_ index: Int, of count: Int) -> Alignment {
        switch (count, index) {
        case (1, _): .center
        case (2, 0): .topLeading
        case (2, _): .bottomTrailing
        case (_, 0): .top
        case (_, 1): .bottomLeading
        default: .bottomTrailing
        }
    }
}

extension ExploreClusterTab {
    var labelResource: String.LocalizationValue {
        switch self {
        case .all: "explore_cluster_tab_all"
        case .venues: "explore_cluster_tab_venues"
        case .activities: "explore_cluster_tab_activities"
        }
    }
}
