import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* 帖子卡片里的链接和照片（Android `PostLinkViews` / `PostPhotos` / `PostFactsBox`，论坛设计稿）。 */

/** 封面上或行标题前的彩色类型标签（活动 / 门店 / 帖子 / 建筑）。 */
struct LinkTypeTag: View {
    let type: PostLinkType
    var label: String?
    var onCover = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.symbol).font(.caption2)
            Group {
                if let label { Text(verbatim: label) } else { Text(type.labelKey) }
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
        }
        .foregroundStyle(type.tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(onCover ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(type.tone.opacity(0.12)), in: .capsule)
    }
}

/** 一行带图标的说明（时间、地点、名额）。 */
private struct LinkFact: View {
    let symbol: String
    let text: String

    var body: some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: symbol) }
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct LinkCover: View {
    let state: LinkCardState
    let type: PostLinkType
    let imageURL: (String?) -> URL?

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if case let .ready(info) = state, let url = imageURL(info.coverImageId) {
                PulsoRemoteImage(url: url)
            } else {
                Image(systemName: type.symbol).foregroundStyle(.secondary)
            }
        }
        .clipShape(.rect(cornerRadius: 6))
    }
}

private struct LinkTitle: View {
    let state: LinkCardState
    let font: Font

    var body: some View {
        switch state {
        case .loading:
            RoundedRectangle(cornerRadius: 4).fill(.fill.tertiary).frame(width: 140, height: 14)
        case .missing:
            Text("discussion_link_missing").font(.subheadline).foregroundStyle(.secondary)
        case let .ready(info):
            Text(verbatim: info.title).font(font.bold()).lineLimit(1)
        }
    }
}

/**
 * 正文链接画成设计稿里的一种卡片：大的活动 / 门店卡、带报名按钮的活动卡、紧凑卡旁边的封面、一行（成组、关联帖子、相关列表）、
 * 照片下面的门店条（Android `LinkTargetCard`）。[onOpen] 打开目标；目标没了显示一张变淡、点不开的卡。
 */
struct LinkTargetCard: View {
    let link: PostLink
    let state: LinkCardState
    let variant: LinkCardVariant
    let imageURL: (String?) -> URL?
    let onOpen: () -> Void
    var label: String?

    @Environment(\.locale) private var locale

    private var info: LinkCardInfo? {
        if case let .ready(info) = state { info } else { nil }
    }

    private var spots: String? {
        info.flatMap { $0.capacity > 0 ? localizedFormat("discussion_card_spots", $0.joined, $0.capacity) : nil }
    }

    var body: some View {
        content
            .opacity(state == .missing ? 0.7 : 1)
            .contentShape(.rect)
            .onTapGesture { if info != nil { onOpen() } }
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .side:
            LinkCover(state: state, type: link.type, imageURL: imageURL)
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(width: 112)
                .overlay(alignment: .bottomLeading) { LinkTypeTag(type: link.type, onCover: true).padding(4) }
        case .row:
            HStack(spacing: 12) {
                LinkCover(state: state, type: link.type, imageURL: imageURL).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    LinkTypeTag(type: link.type, label: label)
                    LinkTitle(state: state, font: .subheadline)
                    if let meta = info?.meta(link.type, locale: locale), !meta.isEmpty {
                        Text(verbatim: meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        case .bar:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label { LinkTitle(state: state, font: .subheadline) } icon: { Image(systemName: PostLinkType.venue.symbol).foregroundStyle(.secondary) }
                    if let address = info?.address, !address.isEmpty { LinkFact(symbol: "mappin.and.ellipse", text: address) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if info != nil {
                    Button("discussion_card_view_venue", action: onOpen).buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        case .inline:
            HStack(alignment: .top, spacing: 12) {
                LinkCover(state: state, type: link.type, imageURL: imageURL).aspectRatio(4 / 3, contentMode: .fit).frame(width: 112)
                VStack(alignment: .leading, spacing: 2) {
                    LinkTitle(state: state, font: .subheadline)
                    if let startsAt = info?.startsAt { LinkFact(symbol: "calendar", text: formatActivityWhen(startsAt, info?.endsAt, locale: locale)) }
                    if let place = info?.place, !place.isEmpty { LinkFact(symbol: "mappin.and.ellipse", text: place) }
                    HStack {
                        if let spots { LinkFact(symbol: "person.2", text: spots) }
                        Spacer(minLength: 4)
                        if info != nil { Button("discussion_card_join_activity", action: onOpen).buttonStyle(.borderedProminent).controlSize(.small) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        case .hero:
            VStack(alignment: .leading, spacing: 0) {
                LinkCover(state: state, type: link.type, imageURL: imageURL)
                    .aspectRatio(16 / 7, contentMode: .fit)
                    .overlay(alignment: link.type == .activity ? .bottomLeading : .topTrailing) { LinkTypeTag(type: link.type, onCover: true).padding(8) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        LinkTitle(state: state, font: .headline).frame(maxWidth: .infinity, alignment: .leading)
                        if link.type != .activity { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    }
                    if let startsAt = info?.startsAt { LinkFact(symbol: "calendar", text: formatActivityWhen(startsAt, info?.endsAt, locale: locale)) }
                    if let place = info?.place, !place.isEmpty { LinkFact(symbol: "mappin.and.ellipse", text: place) }
                    if let spots { LinkFact(symbol: "person.2", text: spots) }
                    if let address = info?.address, !address.isEmpty { LinkFact(symbol: "mappin.and.ellipse", text: address) }
                    if let activityTypes = info?.activityTypes, !activityTypes.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(activityTypes.prefix(4), id: \.self) { activityType in
                                Text(activityType.labelKey).font(.caption2).foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(.fill.tertiary, in: .capsule)
                            }
                        }
                    }
                    if link.type == .activity, info != nil {
                        Button(action: onOpen) { Text("discussion_card_view_activity").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                }
                .padding(12)
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
        }
    }
}

/**
 * 几个链接排成行（Android `PostLinkGroup`）：先显示 [limit] 行，其余收在「还有 N 个链接（1 个活动、1 篇帖子）」后面，
 * 点开就地展开。[title] 是帖子页上这一组的名字。
 */
struct PostLinkGroup: View {
    let links: [PostLink]
    let cards: LinkCards
    let imageURL: (String?) -> URL?
    let onOpen: (PostLink) -> Void
    var title: LocalizedStringKey?
    var limit = postLinkGroupRows

    @State private var open = false

    var body: some View {
        let shown = open ? links : Array(links.prefix(limit))
        let hidden = Array(links.dropFirst(limit))
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.subheadline.bold()).foregroundStyle(.secondary) }
            ForEach(shown, id: \.key) { link in
                LinkTargetCard(
                    link: link,
                    state: cards.states[link.key] ?? .loading,
                    variant: .row,
                    imageURL: imageURL,
                    onOpen: { onOpen(link) },
                    label: link.type == .post ? String(localized: "discussion_card_linked_post") : nil
                )
                .onAppear { cards.ensure(link) }
            }
            if !hidden.isEmpty {
                Button { open.toggle() } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: open ? String(localized: "discussion_card_show_less") : localizedFormat("discussion_card_more_links", hidden.count, breakdown(hidden)))
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.fill.tertiary, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func breakdown(_ hidden: [PostLink]) -> String {
        PostLinkType.allCases.compactMap { type in
            let count = hidden.filter { $0.type == type }.count
            return count > 0 ? type.countText(count) : nil
        }
        .joined(separator: String(localized: "discussion_list_separator"))
    }
}

/**
 * 找球友 / 约球：什么时候、在哪、几个人，和行动按钮（Android `PostFactsBox`）。关联了活动（[activity] 是它的状态）时显示活动的
 * 信息和「报名活动」；没有时显示城市和「我有兴趣」，打开帖子去评论。
 */
struct PostFactsBox: View {
    let activity: LinkCardState?
    let city: String?
    let onJoin: () -> Void
    let onInterested: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let info: LinkCardInfo? = if case let .ready(info) = activity { info } else { nil }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                LinkFact(symbol: "calendar", text: info?.startsAt.map { formatActivityWhen($0, info?.endsAt, locale: locale) } ?? String(localized: "discussion_card_time_open"))
                if let place = activity != nil ? info?.place : city, !place.isEmpty { LinkFact(symbol: "mappin.and.ellipse", text: place) }
                if let info, info.capacity > 0 { LinkFact(symbol: "person.2", text: localizedFormat("discussion_card_spots", info.joined, info.capacity)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if activity == nil {
                Button(action: onInterested) { Label("discussion_card_interested", systemImage: "person") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if info != nil {
                Button("discussion_card_join_activity", action: onJoin).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
    }
}

/**
 * 帖子的照片，按设计稿的一种布局（Android `PostPhotos`）：一张宽图、两张并排、三张一排、一张高的配两张、拼图、2×2，
 * 或（紧凑卡）文字旁边的缩略图 / 小方格。还有更多照片时最后一格写「+N」。[onOpen] 收到点的是第几格。
 */
struct PostPhotos: View {
    let layout: PostPhotoLayout
    let previewIds: [String]
    let imageCount: Int
    let imageURL: (String?) -> URL?
    var onOpen: ((Int) -> Void)?

    private let gap: CGFloat = 4

    var body: some View {
        let tiles = Array(previewIds.prefix(layout.tiles))
        if layout != .none, !tiles.isEmpty {
            let more = hiddenPhotoCount(imageCount, shownTiles: tiles.count)
            switch layout {
            case .none:
                EmptyView()
            case .hero:
                tile(tiles, 0, more).aspectRatio(16 / 9, contentMode: .fit)
            case .side:
                tile(tiles, 0, more).aspectRatio(4 / 3, contentMode: .fit).frame(width: 112)
            case .pair:
                HStack(spacing: gap) { ForEach(tiles.indices, id: \.self) { tile(tiles, $0, more).aspectRatio(4 / 3, contentMode: .fit) } }
            case .strip:
                HStack(spacing: gap) { ForEach(tiles.indices, id: \.self) { tile(tiles, $0, more).aspectRatio(1, contentMode: .fit) } }
            case .split:
                split(tiles, more).aspectRatio(3 / 2, contentMode: .fit)
            case .mosaic:
                VStack(spacing: gap) {
                    split(tiles, more).aspectRatio(3 / 2, contentMode: .fit)
                    if tiles.count > 3 { tile(tiles, 3, more).aspectRatio(3, contentMode: .fit) }
                }
            case .grid, .sideGrid:
                Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                    ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                        GridRow {
                            tile(tiles, start, more, small: layout == .sideGrid).aspectRatio(1, contentMode: .fit)
                            if start + 1 < tiles.count {
                                tile(tiles, start + 1, more, small: layout == .sideGrid).aspectRatio(1, contentMode: .fit)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                .frame(width: layout == .sideGrid ? 112 : nil)
            }
        }
    }

    private func split(_ tiles: [String], _ more: Int) -> some View {
        GeometryReader { proxy in
            HStack(spacing: gap) {
                tile(tiles, 0, more).frame(width: (proxy.size.width - gap) * 2 / 3)
                if tiles.count > 1 {
                    VStack(spacing: gap) {
                        tile(tiles, 1, more)
                        if tiles.count > 2 { tile(tiles, 2, more) }
                    }
                }
            }
        }
    }

    private func tile(_ tiles: [String], _ index: Int, _ more: Int, small: Bool = false) -> some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay { PulsoRemoteImage(url: imageURL(tiles[index])) }
            .overlay {
                if more > 0, index == tiles.count - 1 {
                    ZStack {
                        Color.black.opacity(0.5)
                        Text(verbatim: "+\(more)").font((small ? Font.subheadline : .title2).bold()).foregroundStyle(.white)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture { onOpen?(index) }
    }
}
