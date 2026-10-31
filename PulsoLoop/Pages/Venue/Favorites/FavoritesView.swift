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
 * 关注的论坛（按名字搜）、收藏的帖子和评论也在这里。
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
    private(set) var forumQuery = ""
    private(set) var forums: PagedList<ForumFavorite, Int>
    let posts: PagedList<PostCard, Int>
    let comments: PagedList<CommentBookmark, Int>

    @ObservationIgnored @Injected(\.favoriteService) private var favorites
    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init() {
        let service = Container.shared.favoriteService()
        venues = service.pageVenues(VenueFavoritesFilter())
        buildings = service.pageBuildings(BuildingFavoritesFilter(buildingTypes: BuildingType.loop.map(\.rawValue)))
        let discussion = Container.shared.discussionService()
        forums = discussion.pageFavoriteForums(nil)
        posts = discussion.pageBookmarkedPosts()
        comments = discussion.pageBookmarkedComments()
    }

    var query: String {
        switch tab {
        case .venues: venueControls.query
        case .buildings: buildingControls.query
        default: forumQuery
        }
    }

    func setQuery(_ query: String) {
        switch tab {
        case .venues: setVenueQuery(query)
        case .buildings: setBuildingQuery(query)
        default:
            forumQuery = query
            debounce { self.forums = self.discussion.pageFavoriteForums(self.forumQuery) }
        }
    }

    func unfollowForum(_ forumId: String) async {
        await discussionAct { try await self.discussion.setForumFavorite(forumId, false) }
    }

    func unbookmarkPost(_ postId: String) async {
        await discussionAct {
            try await self.discussion.setPostBookmarked(postId, false)
            self.discussion.invalidate()
        }
    }

    func unbookmarkComment(_ commentId: String) async {
        await discussionAct {
            try await self.discussion.setCommentBookmarked(commentId, false)
            self.discussion.invalidate()
        }
    }

    private func discussionAct(_ block: () async throws -> Void) async {
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
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
        let empty = query.isEmpty
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
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            // 一级标签，下面一行搜索（Android 收藏页：标签在顶栏下、搜索框在标签下）。
            PulsoUnderlineTabRow(FavoritesTab.allCases, selection: $model.tab) { Text($0.labelKey) }
            PulsoSearchField(text: Binding(get: { model.query }, set: { model.setQuery($0) }), prompt: Text(searchPrompt))
                .padding(.horizontal, PulsoSpace.s4)
                .padding(.vertical, PulsoSpace.s2)
            ScrollView {
                LazyVStack(spacing: PulsoSpace.s2) {
                    switch model.tab {
                    case .venues: venueRows
                    case .buildings: buildingRows
                    case .forums: forumRows
                    case .posts: postRows
                    case .comments: commentRows
                    }
                }
                .padding(.horizontal, PulsoSpace.s4)
                .padding(.vertical, PulsoSpace.s2)
            }
            .refreshable {
                switch model.tab {
                case .venues: await model.venues.refresh()
                case .buildings: await model.buildings.refresh()
                case .forums: await model.forums.refresh()
                case .posts: await model.posts.refresh()
                case .comments: await model.comments.refresh()
                }
            }
        }
        .navigationTitle("favorites_title")
        .toolbar {
            if model.tab == .venues || model.tab == .buildings {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { filtersOpen = true } label: { Label("favorites_filter_open", systemImage: "slider.horizontal.3") }
                        .badge(model.tab == .venues ? model.venueControls.activeFilterCount : model.buildingControls.activeFilterCount)
                }
            }
        }
        .sheet(isPresented: $filtersOpen) {
            FavoritesFilterSheet(model: model)
        }
        .task { await model.observe() }
        .task(id: ObjectIdentifier(model.venues)) { await model.venues.observe() }
        .task(id: ObjectIdentifier(model.buildings)) { await model.buildings.observe() }
        .task(id: ObjectIdentifier(model.forums)) { await model.forums.observe() }
        .task { await model.posts.observe() }
        .task { await model.comments.observe() }
    }

    /** 一张收藏卡片：面板底、卡片圆角，内边距 16。 */
    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        PulsoCard { content().padding(PulsoSpace.s4) }
    }

    /** 红色实心爱心：点了取消收藏（Android 收藏卡片右上角）。 */
    private func heart(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(palette.error)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("favorites_remove_saved"))
    }

    private func emptyText(_ key: LocalizedStringKey) -> some View {
        PulsoEmptyState(Text(key)).frame(minHeight: 360)
    }

    private var searchPrompt: LocalizedStringKey {
        switch model.tab {
        case .venues: "favorites_search_venues"
        case .buildings: "favorites_search_buildings"
        default: "favorites_search_forums"
        }
    }

    /* ------------------------------ 论坛 / 帖子 / 评论 ------------------------------ */

    @ViewBuilder
    private var forumRows: some View {
        favoriteRows(model.forums, empty: model.forumQuery.isEmpty ? "favorites_empty_forums" : "favorites_no_results") { row in
            Button { shell?.push(LoopRoute.forum(forumId: row.forumId)) } label: {
                ForumRowView(
                    name: row.name, ownerScope: row.owner.profileScope, sports: row.sports, description: row.description,
                    favoriteCount: row.favoriteCount, postCount: row.postCount,
                    avatarURL: model.imageURL(row.avatarImageId), coverURL: model.imageURL(row.coverImageId),
                    favorited: true, onToggleFollow: { Task { await model.unfollowForum(row.forumId) } }
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var postRows: some View {
        favoriteRows(model.posts, empty: "favorites_empty_posts") { post in
            PostCardView(
                post: post,
                imageURL: { model.imageURL($0) },
                onOpen: { shell?.push(LoopRoute.post(postId: post.id)) },
                onLike: {},
                onBookmark: { Task { await model.unbookmarkPost(post.id) } },
                onOpenForum: { shell?.push(LoopRoute.forum(forumId: $0)) }
            )
        }
    }

    @ViewBuilder
    private var commentRows: some View {
        favoriteRows(model.comments, empty: "favorites_empty_comments") { row in
            VStack(alignment: .leading, spacing: 6) {
                Button { shell?.push(LoopRoute.post(postId: row.postId)) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: localizedFormat("favorites_comment_on", row.postTitle)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        AuthorLine(author: row.author, at: row.createdAt, avatarURL: model.imageURL(row.author.avatarImageId))
                        RichTextBody(html: row.contentHtml, lineLimit: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                HStack {
                    Spacer()
                    Button("favorites_remove_saved") { Task { await model.unbookmarkComment(row.commentId) } }
                        .buttonStyle(.pulso(.soft, tone: .gray, size: .small))
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteRows<Item: Sendable, Row: View>(
        _ list: PagedList<Item, Int>, empty: LocalizedStringKey, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View where Item: Identifiable {
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, PulsoSpace.s8)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            emptyText(empty)
        } else {
            ForEach(list.items) { item in
                card { row(item) }.onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }

    @ViewBuilder
    private var venueRows: some View {
        let list = model.venues
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, PulsoSpace.s8)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            emptyText((model.venueControls.query.isEmpty && model.venueControls.filter == nil ? "favorites_empty_venues" : "favorites_no_results") as LocalizedStringKey)
        } else {
            ForEach(list.items, id: \.id) { item in
                card {
                    HStack(alignment: .top, spacing: PulsoSpace.s3) {
                        NavigationLink(value: LoopRoute.venue(venueId: item.venueId)) {
                            HStack(alignment: .top, spacing: PulsoSpace.s3) {
                                SportCover(url: model.imageURL(item.coverImageId), sport: item.venueSports.first?.loopSport ?? .badminton, iconSize: 24)
                                    .frame(width: 88, height: 112)
                                    .clipShape(palette.innerShape)
                                VStack(alignment: .leading, spacing: PulsoSpace.s1) {
                                    Text(verbatim: item.building.name).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text).lineLimit(2)
                                    if !item.building.address.isEmpty {
                                        Text(verbatim: item.building.address).font(.caption).foregroundStyle(palette.secondaryText).lineLimit(1)
                                    }
                                    HStack(spacing: PulsoSpace.s1) {
                                        if let status = venueOpenStatus(venueWeek(item.hours), timezone: item.venueTimezone) {
                                            VenueOpenChip(status: status)
                                        }
                                        Text(verbatim: localizedFormat("shell_views_count", item.venueView)).font(.caption2).foregroundStyle(palette.secondaryText)
                                    }
                                    PulsoFlowLayout(spacing: PulsoSpace.s1) {
                                        ForEach(item.venueSports, id: \.self) { SportTag(sport: $0.loopSport) }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        VStack {
                            heart { Task { await model.unfavorite(.venue, id: item.venueId) } }
                            Spacer(minLength: PulsoSpace.s2)
                            if let sport = item.venueSports.first {
                                NavigationLink("favorites_book", value: LoopRoute.venueBook(venueId: item.venueId, sport: sport))
                                    .buttonStyle(.pulso(size: .small))
                            }
                        }
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
            ProgressView().frame(maxWidth: .infinity).padding(.top, PulsoSpace.s8)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            emptyText((model.buildingControls.query.isEmpty && model.buildingControls.filter == nil ? "favorites_empty_buildings" : "favorites_no_results") as LocalizedStringKey)
        } else {
            ForEach(list.items, id: \.id) { item in
                card {
                    HStack(alignment: .top, spacing: PulsoSpace.s3) {
                        NavigationLink(value: LoopRoute.building(buildingId: item.buildingId)) {
                            HStack(spacing: PulsoSpace.s3) {
                                let visual = BuildingTypeVisual.of(item.buildingType)
                                Image(systemName: visual.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(visual.accent)
                                    .frame(width: 48, height: 48)
                                    .background(visual.accentBg, in: palette.innerShape)
                                VStack(alignment: .leading, spacing: PulsoSpace.half) {
                                    Text(verbatim: item.name).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text).lineLimit(2)
                                    Text(BuildingType.fromWire(item.buildingType).labelKey).font(.caption).foregroundStyle(palette.secondaryText)
                                    if !item.address.isEmpty {
                                        Text(verbatim: item.address).font(.caption).foregroundStyle(palette.secondaryText).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        heart { Task { await model.unfavorite(.building, id: item.buildingId) } }
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

extension ForumFavorite: Identifiable {}
extension CommentBookmark: Identifiable {}
