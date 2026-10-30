import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 收藏页的一个地点分段的工具栏：搜索词、筛选、排序（Android `FavoritesControls`）。 */
struct FavoritesControls<Filter: Hashable>: Hashable {
    var query = ""
    var filter: Filter?
    var sort = PlaceSort.fallback

    /** 和默认值不同的筛选数（筛选按钮的角标）。 */
    var activeFilterCount: Int { (filter != nil ? 1 : 0) + (sort != .fallback ? 1 : 0) }
}

/**
 * 收藏（Android `FavoritesViewModel`）：收藏的球馆和建筑，各自在服务端搜索、筛选、排序并分页；取消收藏后列表和数量都重拉。
 * 论坛 / 帖子 / 评论三个分段在第 11 组接上。
 */
@MainActor
@Observable
final class FavoritesModel {
    static let searchDebounce = Duration.milliseconds(300)

    var tab = FavoritesTab.venues
    private(set) var venueControls = FavoritesControls<VenueSport>()
    private(set) var buildingControls = FavoritesControls<String>()
    private(set) var venues: PagedList<VenueFavoriteItem, Int>
    private(set) var buildings: PagedList<BuildingFavoriteItem, Int>
    private(set) var venueCounts: VenueFavoriteCounts?
    private(set) var buildingCounts: BuildingFavoriteCounts?
    /** 设备位置；有了才能按距离排。 */
    private(set) var origin: GeoPoint?

    @ObservationIgnored @Injected(\.favoriteService) private var favorites
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init() {
        let service = Container.shared.favoriteService()
        venues = service.pageVenues(VenueFavoritesFilter())
        buildings = service.pageBuildings(BuildingFavoritesFilter(buildingTypes: BuildingType.loop.map(\.rawValue)))
    }

    var canSortByDistance: Bool { origin != nil }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        await concurrently([
            {
                for await device in self.deviceLocation.location.values() {
                    let next = device.map { GeoPoint(longitude: $0.point.longitude, latitude: $0.point.latitude) }
                    guard next != self.origin else { continue }
                    self.origin = next
                    if self.venueControls.sort == .nearest { self.reloadVenues() }
                    if self.buildingControls.sort == .nearest { self.reloadBuildings() }
                }
            },
            {
                await self.loadCounts()
                for await _ in self.favorites.changes.signals(where: { _ in true }) {
                    await self.loadCounts()
                }
            },
        ])
    }

    private func loadCounts() async {
        venueCounts = try? await favorites.venueCounts()
        buildingCounts = try? await favorites.buildingCounts()
    }

    func setVenueQuery(_ query: String) {
        venueControls.query = query
        debounce { self.reloadVenues() }
    }

    func setBuildingQuery(_ query: String) {
        buildingControls.query = query
        debounce { self.reloadBuildings() }
    }

    /** 筛选面板里的排序和运动，一次更新（一次重拉）。 */
    func applyVenueFilters(sort: PlaceSort, sport: VenueSport?) {
        venueControls.sort = sort
        venueControls.filter = sport
        reloadVenues()
    }

    func applyBuildingFilters(sort: PlaceSort, type: String?) {
        buildingControls.sort = sort
        buildingControls.filter = type
        reloadBuildings()
    }

    func unfavorite(_ target: FavoriteTarget, id: String) async {
        do {
            try await favorites.setFavorite(target, id: id, favorite: false)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "favorites_toggle_failed")
        }
    }

    /** 搜索词停下 0.3 秒再重拉；清空时马上。 */
    private func debounce(_ action: @escaping @MainActor () -> Void) {
        debounceTask?.cancel()
        let empty = tab == .venues ? venueControls.query.isEmpty : buildingControls.query.isEmpty
        debounceTask = Task {
            if !empty { try? await Task.sleep(for: Self.searchDebounce) }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func reloadVenues() {
        venues = favorites.pageVenues(VenueFavoritesFilter(
            search: venueControls.query.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: venueControls.filter,
            sort: venueControls.sort,
            near: origin
        ))
    }

    private func reloadBuildings() {
        buildings = favorites.pageBuildings(BuildingFavoritesFilter(
            search: buildingControls.query.trimmingCharacters(in: .whitespacesAndNewlines),
            buildingTypes: buildingControls.filter.map { [$0] } ?? BuildingType.loop.map(\.rawValue),
            sort: buildingControls.sort,
            near: origin
        ))
    }
}

/** 收藏（Android `FavoritesScreen`）：球馆 / 建筑 / 论坛 / 帖子 / 评论分段；地点分段有搜索、筛选和排序，左滑取消收藏。 */
struct FavoritesView: View {
    @State private var model = FavoritesModel()
    @State private var filtersOpen = false

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FavoritesTab.allCases, id: \.self) { tab in
                            let isOn = tab == model.tab
                            Button { model.tab = tab } label: {
                                Text(tab.labelKey)
                                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .foregroundStyle(isOn ? Color.white : Color.primary)
                                    .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
            switch model.tab {
            case .venues: venueRows
            case .buildings: buildingRows
            case .forums, .posts, .comments:
                PulsoComingSoonView(title: model.tab.labelKey, systemImage: "bubble.left.and.text.bubble.right")
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("favorites_title")
        .toolbar {
            if model.tab == .venues || model.tab == .buildings {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { filtersOpen = true } label: { Label("favorites_filter_open", systemImage: "line.3.horizontal.decrease") }
                        .badge(model.tab == .venues ? model.venueControls.activeFilterCount : model.buildingControls.activeFilterCount)
                }
            }
        }
        .searchable(text: Binding(
            get: { model.tab == .venues ? model.venueControls.query : model.buildingControls.query },
            set: { model.tab == .venues ? model.setVenueQuery($0) : model.setBuildingQuery($0) }
        ), prompt: Text((model.tab == .venues ? "favorites_search_venues" : "favorites_search_buildings") as LocalizedStringKey))
        .sheet(isPresented: $filtersOpen) {
            FavoritesFilterSheet(model: model)
        }
        .refreshable {
            if model.tab == .venues { await model.venues.refresh() } else { await model.buildings.refresh() }
        }
        .task { await model.observe() }
        .task(id: ObjectIdentifier(model.venues)) { await model.venues.observe() }
        .task(id: ObjectIdentifier(model.buildings)) { await model.buildings.observe() }
    }

    @ViewBuilder
    private var venueRows: some View {
        let list = model.venues
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
        } else if list.isEmpty {
            Text((model.venueControls.query.isEmpty && model.venueControls.filter == nil ? "favorites_empty_venues" : "favorites_no_results") as LocalizedStringKey)
                .font(.subheadline).foregroundStyle(.secondary).listRowBackground(Color.clear)
        } else {
            ForEach(list.items, id: \.id) { item in
                NavigationLink(value: LoopRoute.venue(venueId: item.venueId)) {
                    HStack(spacing: 12) {
                        SportCover(url: model.imageURL(item.coverImageId), sport: item.venueSports.first?.loopSport ?? .badminton, iconSize: 24)
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: item.building.name).font(.headline).lineLimit(2)
                            if !item.building.address.isEmpty {
                                Text(verbatim: item.building.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let status = venueOpenStatus(venueWeek(item.hours), timezone: item.venueTimezone) {
                                VenueOpenChip(status: status)
                            }
                            PulsoFlowLayout(spacing: 4) {
                                ForEach(item.venueSports, id: \.self) { SportTag(sport: $0.loopSport) }
                            }
                            Text(verbatim: localizedFormat("shell_views_count", item.venueView)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("favorites_remove_saved", systemImage: "heart.slash", role: .destructive) {
                        Task { await model.unfavorite(.venue, id: item.venueId) }
                    }
                    if let sport = item.venueSports.first {
                        NavigationLink(value: LoopRoute.venueBook(venueId: item.venueId, sport: sport)) {
                            Label("favorites_book", systemImage: "calendar.badge.plus")
                        }
                        .tint(.accentColor)
                    }
                }
                .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }

    @ViewBuilder
    private var buildingRows: some View {
        let list = model.buildings
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
        } else if list.isEmpty {
            Text((model.buildingControls.query.isEmpty && model.buildingControls.filter == nil ? "favorites_empty_buildings" : "favorites_no_results") as LocalizedStringKey)
                .font(.subheadline).foregroundStyle(.secondary).listRowBackground(Color.clear)
        } else {
            ForEach(list.items, id: \.id) { item in
                NavigationLink(value: LoopRoute.building(buildingId: item.buildingId)) {
                    HStack(spacing: 12) {
                        let visual = BuildingTypeVisual.of(item.buildingType)
                        Image(systemName: visual.systemImage)
                            .font(.title3)
                            .foregroundStyle(visual.accent)
                            .frame(width: 48, height: 48)
                            .background(visual.accentBg, in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: item.name).font(.headline).lineLimit(2)
                            Text(BuildingType.fromWire(item.buildingType).labelKey).font(.caption).foregroundStyle(.secondary)
                            if !item.address.isEmpty {
                                Text(verbatim: item.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("favorites_remove_saved", systemImage: "heart.slash", role: .destructive) {
                        Task { await model.unfavorite(.building, id: item.buildingId) }
                    }
                }
                .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }
}

/** 收藏的筛选（Android `FavoritesFilterSheet`）：排序（有位置才有「最近」），球馆按运动、建筑按类型，带数量。 */
private struct FavoritesFilterSheet: View {
    let model: FavoritesModel

    @Environment(\.dismiss) private var dismiss
    @State private var sort = PlaceSort.fallback
    @State private var sport: VenueSport?
    @State private var type: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker(selection: $sort) {
                    ForEach(PlaceSort.allCases.filter { $0 != .nearest || model.canSortByDistance }, id: \.self) { sort in
                        Text(sort.labelKey).tag(sort)
                    }
                } label: {
                    Text("favorites_sort")
                }
                if model.tab == .venues {
                    Picker(selection: $sport) {
                        Text(verbatim: countLabel(String(localized: "favorites_filter_all"), model.venueCounts?.total)).tag(VenueSport?.none)
                        ForEach(VenueSport.allCases, id: \.self) { sport in
                            Text(verbatim: countLabel(String(localized: sport.loopSport.labelResource), model.venueCounts?.bySport.first { $0.sport == sport }?.count)).tag(VenueSport?.some(sport))
                        }
                    } label: {
                        Text("favorites_filter_sport")
                    }
                } else {
                    Picker(selection: $type) {
                        Text(verbatim: countLabel(String(localized: "favorites_filter_all"), model.buildingCounts?.total)).tag(String?.none)
                        ForEach(BuildingType.loop, id: \.self) { type in
                            Text(verbatim: countLabel(String(localized: type.labelResource), model.buildingCounts?.byBuildingType.first { $0.buildingType == type.rawValue }?.count)).tag(String?.some(type.rawValue))
                        }
                    } label: {
                        Text("favorites_filter_type")
                    }
                }
            }
            .navigationTitle("favorites_filter_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("nearby_filter_reset") {
                        sort = .fallback
                        sport = nil
                        type = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if model.tab == .venues { model.applyVenueFilters(sort: sort, sport: sport) } else { model.applyBuildingFilters(sort: sort, type: type) }
                        dismiss()
                    } label: {
                        Text("nearby_filter_apply")
                    }
                }
            }
        }
        .onAppear {
            sort = model.tab == .venues ? model.venueControls.sort : model.buildingControls.sort
            sport = model.venueControls.filter
            type = model.buildingControls.filter
        }
        .presentationDetents([.medium])
    }

    private func countLabel(_ name: String, _ count: Int?) -> String {
        count.map { localizedFormat("favorites_filter_count", name, $0) } ?? name
    }
}

extension PlaceSort {
    var labelKey: LocalizedStringKey {
        switch self {
        case .recent: "favorites_sort_recent"
        case .nearest: "favorites_sort_nearest"
        case .name: "favorites_sort_name"
        }
    }
}
