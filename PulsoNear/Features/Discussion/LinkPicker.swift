import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 链接选择器里能选的一行：指向什么、标题、一行说明、封面（Android `LinkPickerRow`）。 */
struct LinkPickerRow: Identifiable, Codable, Sendable {
    let link: PostLink
    let title: String
    let meta: String
    let coverImageId: String?

    var id: String { link.key }
}

/**
 * 链接选择器（Android `LinkPickerViewModel`）：在信息流里搜帖子，在手机附近（或城市中心）30 公里内搜活动、门店和场馆建筑，
 * 每个标签一个分页列表；粘贴的 Near 页面链接直接变成目标。
 */
@MainActor
@Observable
final class LinkPickerModel {
    private static let radiusM = 30_000
    private static let buildingsLimit = 50

    var tab: PostLinkType = .activity { didSet { if tab != oldValue { reload() } } }
    var query = ""
    var pasted = "" { didSet { pasteInvalid = false } }
    private(set) var pasteInvalid = false
    private(set) var rows: any PagedRows<LinkPickerRow>
    /** 每次换标签或搜索词加一，页面用它重启列表的 `.task`。 */
    private(set) var generation = 0

    @ObservationIgnored private let discussion: DiscussionService
    @ObservationIgnored private let explore: ExploreRepository
    @ObservationIgnored private let venues: VenueRepository
    @ObservationIgnored private let buildings: BuildingService
    @ObservationIgnored private let deviceLocation: DeviceLocationStore
    @ObservationIgnored private var appliedQuery = ""

    init(container: Container = .shared) {
        discussion = container.discussionService()
        explore = ExploreRepository(publicAPI: ExplorePublicAPI(client: container.publicClient()))
        venues = container.venueRepository()
        buildings = container.buildingService()
        deviceLocation = container.deviceLocationStore()
        rows = PagedList<LinkPickerRow, Int>.offset { _, _ in ListWithTotal(items: [], total: 0) }
        reload()
    }

    /** 搜索词停 300ms 再搜（Android `SEARCH_DEBOUNCE_MS`）。 */
    func search(_ value: String) async {
        try? await Task.sleep(for: .milliseconds(300))
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !Task.isCancelled, trimmed != appliedQuery else { return }
        appliedQuery = trimmed
        reload()
    }

    /** 粘贴的链接能认出来就返回目标，否则输入框下提示原因。 */
    func pastedLink() -> PostLink? {
        let link = PostLinkLoader.parse(pasted)
        if link == nil { pasteInvalid = true }
        return link
    }

    private func near() -> GeoNearQuery {
        let point = deviceLocation.location.value?.point
        return GeoNearQuery(
            longitude: point?.longitude ?? MapConstants.fallbackCenter.longitude,
            latitude: point?.latitude ?? MapConstants.fallbackCenter.latitude,
            radiusM: Self.radiusM
        )
    }

    private func reload() {
        let search: String? = appliedQuery.isEmpty ? nil : appliedQuery
        let near = near()
        let locale = Locale.current
        switch tab {
        case .post:
            rows = discussion.pageFeed(tab: .latest, activityType: nil, forumId: nil, search: search).mapped { post in
                LinkPickerRow(
                    link: PostLink(type: .post, id: post.id),
                    title: post.title,
                    meta: [post.author.displayName, post.forums.first?.forumName].compactMap { $0 }.joined(separator: " · "),
                    coverImageId: post.previewImageIds.first
                )
            }
        case .activity:
            let explore = explore
            rows = PagedList<ExplorePin, Int>.offset { offset, limit in
                let page = try await explore.listNearbyPins(ListNearbyPinsRequest(near: near, includeEnded: true, search: search, offset: offset, limit: limit, summary: false))
                return ListWithTotal(items: page.items, total: page.total)
            }
            .mapped { pin in
                LinkPickerRow(
                    link: PostLink(type: .activity, id: pin.id, activityType: pin.activityType),
                    title: pin.title,
                    meta: [DateTimeFormatters.monthDayTime(pin.startsAt, locale: locale), pin.venueName].compactMap { $0 }.joined(separator: " · "),
                    coverImageId: pin.imageId
                )
            }
        case .venue:
            let venues = venues
            rows = PagedList<NearbyVenuePin, Int>.offset { offset, limit in
                let page = try await venues.listNearbyVenues(ListNearbyVenuesRequest(near: near, search: search, offset: offset, limit: limit))
                return ListWithTotal(items: page.items, total: page.total)
            }
            .mapped { venue in
                LinkPickerRow(link: PostLink(type: .venue, id: venue.id), title: venue.building.name, meta: venue.building.address, coverImageId: venue.coverImageId)
            }
        case .building:
            let buildings = buildings
            // 附近场馆建筑没有 offset：只取最近的一页。
            rows = PagedList<BuildingItem, Int>.offset(pageSize: Self.buildingsLimit) { offset, _ in
                guard offset == 0 else { return ListWithTotal(items: [], total: 0) }
                let list = try await buildings.listNearbyBuildings(
                    lat: near.latitude, lng: near.longitude, radiusM: Self.radiusM, search: search,
                    buildingTypes: BuildingType.near.map(\.rawValue), limit: Self.buildingsLimit
                )
                return ListWithTotal(items: list.items, total: list.items.count)
            }
            .mapped { building in
                LinkPickerRow(link: PostLink(type: .building, id: building.id), title: building.name, meta: building.address, coverImageId: building.coverImageId)
            }
        }
        generation += 1
    }
}

/** 选链接段指向什么：粘贴一个 Near 页面链接，或者搜帖子、活动、门店、场馆建筑（Android `LinkPickerSheet`）。 */
struct LinkPickerSheet: View {
    let imageURL: (String?) -> URL?
    let onPick: (PostLink) -> Void
    @State private var model = LinkPickerModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("discussion_link_picker_paste_placeholder", text: $model.pasted)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("discussion_link_picker_paste_add") {
                            if let link = model.pastedLink() { pick(link) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text((model.pasteInvalid ? "discussion_link_picker_paste_invalid" : "discussion_link_picker_paste_hint") as LocalizedStringKey)
                        .foregroundStyle(model.pasteInvalid ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Section {
                    Picker("discussion_link_picker_title", selection: $model.tab) {
                        ForEach(PostLinkType.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    TextField(searchPlaceholder, text: $model.query)
                        .task(id: model.query) { await model.search(model.query) }
                }
                Section { results }
            }
            .navigationTitle("discussion_link_picker_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .task(id: model.generation) { await model.rows.observe() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var results: some View {
        let rows = model.rows
        if rows.isLoading {
            ForEach(0 ..< 4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary).frame(height: 48)
            }
        } else if let error = rows.error {
            PulsoLoadErrorView(error) { Task { await rows.refresh() } }
        } else if rows.isEmpty {
            Text("discussion_link_picker_empty").font(.footnote).foregroundStyle(.secondary)
        } else {
            ForEach(rows.items) { row in
                Button { pick(row.link) } label: { PickerRow(row: row, imageURL: imageURL) }
                    .buttonStyle(.plain)
                    .onAppear { if row.id == rows.items.last?.id { rows.loadMore() } }
            }
        }
    }

    private var searchPlaceholder: LocalizedStringKey {
        switch model.tab {
        case .post: "discussion_link_picker_search_post"
        case .activity: "discussion_link_picker_search_activity"
        case .venue: "discussion_link_picker_search_venue"
        case .building: "discussion_link_picker_search_building"
        }
    }

    private func pick(_ link: PostLink) {
        onPick(link)
        dismiss()
    }
}

private struct PickerRow: View {
    let row: LinkPickerRow
    let imageURL: (String?) -> URL?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                if let url = imageURL(row.coverImageId) {
                    PulsoRemoteImage(url: url)
                } else {
                    Image(systemName: row.link.type.symbol).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 42)
            .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if !row.meta.isEmpty {
                    Text(verbatim: row.meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
