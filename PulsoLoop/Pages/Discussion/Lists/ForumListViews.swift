import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* 论坛的几张列表页：发现论坛（搜索）、我的论坛、我赞过的帖子（Android `pages/discussion/search|mine|liked`）。 */

/** 按名字、类型、运动和排序找论坛；行里直接关注 / 取消（Android `ForumSearchViewModel`）。 */
@MainActor
@Observable
final class ForumSearchModel {
    var query = ""
    var owner: ForumOwnerFilter = .all { didSet { if owner != oldValue { reload() } } }
    var sport: ForumSport? { didSet { if sport != oldValue { reload() } } }
    var sort: ForumSort = .popular { didSet { if sort != oldValue { reload() } } }
    private(set) var forums: PagedList<ForumItem, Int>
    private(set) var busyId: String?
    private(set) var generation = 0

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var appliedQuery = ""

    init() {
        forums = Container.shared.discussionService().pageForums(ListForumsRequest(sort: ForumSort.popular.rawValue))
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    /** 有字时停 300ms 再搜，清空立即。 */
    func queryChanged() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled, trimmed != appliedQuery else { return }
        appliedQuery = trimmed
        reload()
    }

    /** 先改，失败退回。 */
    func toggleFollow(_ forum: ForumItem) async {
        let next = !forum.favoritedByMe
        flip(forum.id, next)
        busyId = forum.id
        defer { busyId = nil }
        do {
            try await discussion.setForumFavorite(forum.id, next)
        } catch {
            flip(forum.id, !next)
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    private func flip(_ id: String, _ on: Bool) {
        forums.update(where: { $0.id == id }) {
            $0.favoritedByMe = on
            $0.favoriteCount = max(0, $0.favoriteCount + (on ? 1 : -1))
        }
    }

    private func reload() {
        forums = discussion.pageForums(ListForumsRequest(
            search: appliedQuery.isEmpty ? nil : appliedQuery, sport: sport, ownerScope: owner.wire, sort: sort.rawValue
        ))
        generation += 1
    }
}

/** 发现论坛（Android `ForumSearchScreen`）：搜索框随列表滚走，类型切换和运动 / 排序筛选固定在上面；右上角建论坛。 */
struct ForumSearchView: View {
    @State private var model = ForumSearchModel()
    @Environment(\.pulsoPalette) private var palette
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: PulsoSpace.s3, pinnedViews: .sectionHeaders) {
                PulsoSearchField(text: $model.query, prompt: Text("discussion_search_forums_placeholder"))
                    .padding(.horizontal, PulsoSpace.s4)
                Section {
                    rows.padding(.horizontal, PulsoSpace.s4)
                } header: {
                    filters
                }
            }
            .padding(.vertical, PulsoSpace.s3)
        }
        .navigationTitle("discussion_search_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: LoopRoute.forumCreate) { Image(systemName: "plus") }
                    .accessibilityLabel(Text("discussion_create_forum"))
            }
        }
        .refreshable { await model.forums.refresh() }
        .task(id: model.generation) { await model.forums.observe() }
        .task(id: model.query) { await model.queryChanged() }
    }

    /** 类型切换和运动 / 排序筛选吸顶（Android 发现论坛）。 */
    private var filters: some View {
        VStack(spacing: PulsoSpace.s3) {
            PulsoSegmentedControl(ForumOwnerFilter.allCases, selection: $model.owner) { Text($0.labelKey) }
                .padding(.horizontal, PulsoSpace.s4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PulsoSpace.s2) {
                    PulsoChoiceChip(Text("discussion_all_sports"), selected: model.sport == nil) { model.sport = nil }
                    ForEach(ForumSport.allCases, id: \.self) { sport in
                        PulsoChoiceChip(Text(sport.labelKey), image: sport.sport.map { Image($0.iconAsset) }, selected: model.sport == sport) { model.sport = sport }
                    }
                    ForEach(ForumSort.allCases, id: \.self) { sort in
                        PulsoChoiceChip(Text(sort.labelKey), selected: model.sort == sort) { model.sort = sort }
                    }
                }
                .padding(.horizontal, PulsoSpace.s4)
            }
        }
        .padding(.vertical, PulsoSpace.s2)
        .background(palette.background)
    }

    @ViewBuilder
    private var rows: some View {
        let list = model.forums
        if list.isLoading {
            ForEach(0 ..< 4, id: \.self) { _ in palette.cardShape.fill(palette.gray.step(3)).frame(height: 120) }
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            PulsoEmptyState(Text("discussion_search_empty"), description: Text("discussion_search_empty_body")) {
                NavigationLink("discussion_create_forum", value: LoopRoute.forumCreate).buttonStyle(.pulso())
            }
        } else {
            ForEach(list.items, id: \.id) { forum in
                Button { shell?.push(LoopRoute.forum(forumId: forum.id)) } label: {
                    PulsoCard {
                        ForumRowView(forum: forum, imageURL: model.imageURL, busy: model.busyId == forum.id) {
                            Task { await model.toggleFollow(forum) }
                        }
                        .padding(PulsoSpace.s4)
                    }
                }
                .buttonStyle(.plain)
                .onAppear { if forum.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }
}

extension MyForum: Identifiable {
    /** 版主只能看论坛和待审的帖子；所有者和管理员才能管理。 */
    var canManage: Bool { role == .owner || role == .admin }
}

/** 我建的或帮忙管理的论坛，每个论坛等我处理的事（Android `MyForumsScreen`）。 */
struct MyForumsView: View {
    @State private var forums = Container.shared.discussionService().pageMyForums()
    @Injected(\.pulsoCoreConfig) private var config

    var body: some View {
        PulsoPagedList(list: forums, emptyTitle: "discussion_my_forums_empty", emptyBody: "discussion_my_forums_empty_body") {
            NavigationLink("discussion_create_forum", value: LoopRoute.forumCreate).buttonStyle(.pulso())
        } header: {
            // 「创建论坛」是一整行柔和按钮（Android 我的论坛顶部）。
            NavigationLink(value: LoopRoute.forumCreate) {
                Label("discussion_create_forum", systemImage: "plus")
            }
            .buttonStyle(.pulso(.soft, fullWidth: true))
        } row: { forum in
            row(forum)
        }
        .navigationTitle("discussion_my_forums")
    }

    private func row(_ forum: MyForum) -> some View {
        let waiting = forum.pendingPostCount + forum.pendingRequestCount + forum.openReportCount
        let imageURL = { (id: String?) in ImageURLs.image(id, base: config.apiBaseURL) }
        return VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: LoopRoute.forum(forumId: forum.id)) {
                ForumRowView(
                    name: forum.name, ownerScope: forum.owner.profileScope, sports: forum.sports, description: forum.description,
                    favoriteCount: forum.favoriteCount, postCount: forum.postCount,
                    avatarURL: imageURL(forum.avatarImageId), coverURL: imageURL(forum.coverImageId)
                )
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: [String(localized: forum.role.labelResource), forum.status == .archived ? String(localized: "discussion_forum_archived_short") : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(Color.accentColor)
                    Text(verbatim: waiting == 0
                        ? String(localized: "discussion_my_forums_all_clear")
                        : localizedFormat("discussion_my_forums_waiting", forum.pendingPostCount, forum.pendingRequestCount, forum.openReportCount))
                        .font(.caption).foregroundStyle(waiting == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
                Spacer()
                if forum.canManage {
                    NavigationLink("discussion_manage", value: LoopRoute.forumManage(forumId: forum.id))
                        .buttonStyle(.pulso(.soft))
                        .controlSize(.small)
                }
            }
        }
    }
}

/** 我赞过的帖子，最新的在前；取消赞后下次重拉时这一行就没了（Android `LikedPostsScreen`）。 */
@MainActor
@Observable
final class LikedPostsModel {
    let posts: PagedList<PostCard, Int>
    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init() {
        posts = Container.shared.discussionService().pageLikedPosts()
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    func toggleLike(_ post: PostCard) async {
        await act { try await self.discussion.setPostLiked(post.id, !post.likedByMe) }
    }

    func toggleBookmark(_ post: PostCard) async {
        await act { try await self.discussion.setPostBookmarked(post.id, !post.bookmarkedByMe) }
    }

    private func act(_ block: () async throws -> Void) async {
        do {
            try await block()
            discussion.invalidate()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }
}

struct LikedPostsView: View {
    @State private var model = LikedPostsModel()
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        PulsoPagedList(list: model.posts, emptyTitle: "discussion_liked_empty", emptyBody: "discussion_liked_empty_body") {
            Button("discussion_browse_feed") { shell?.open(.forum) }.buttonStyle(.pulso())
        } row: { post in
            PostCardView(
                post: post,
                imageURL: model.imageURL,
                onOpen: { shell?.push(LoopRoute.post(postId: post.id)) },
                onLike: { Task { await model.toggleLike(post) } },
                onBookmark: { Task { await model.toggleBookmark(post) } },
                onOpenForum: { shell?.push(LoopRoute.forum(forumId: $0)) }
            )
        }
        .navigationTitle("discussion_liked_title")
    }
}
