import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 发帖页的起点：要写的活动、要转发的帖子，或已经选好的论坛（Android `PostCreatePrefill`）。 */
struct PostCreatePrefill: Hashable, Sendable {
    var eventSport: LoopSport?
    var eventId: String?
    var repostOfPostId: String?
    var forumId: String?
    /** 一开始选好的类型，比如给新活动招人时是「找球友」。 */
    var kind: PostKind?
}

/**
 * 论坛信息流（Android `ForumFeedViewModel`）：最新 / 热门 / 关注 / 我的；运动筛选、搜帖子、只看一个论坛；
 * 点赞和收藏先改，失败退回。
 */
@MainActor
@Observable
final class ForumFeedModel {
    var tab = ForumFeedTab.latest { didSet { if tab != oldValue { reload() } } }
    var sport: ForumSport? { didSet { if sport != oldValue { reload() } } }
    private(set) var forum: ForumItem?
    var query = "" { didSet { if query != oldValue { scheduleReload() } } }
    var pickerOpen = false
    var reporting: PostCard?
    private(set) var reportBusy = false
    private(set) var pendingTotal = 0
    private(set) var posts: PagedList<PostCard, String>
    let myPosts: PagedList<ForumPost, Int>
    private(set) var generation = 0

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var debounce: Task<Void, Never>?

    init() {
        let service = Container.shared.discussionService()
        posts = service.pageFeed(tab: .latest, sport: nil, forumId: nil)
        myPosts = service.pageMyPosts()
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    /** 待处理（审帖 + 申请 + 举报）总数，「我的论坛」上的红点。 */
    func observeIndicators() async {
        pendingTotal = (try? await discussion.indicators()).map { $0.pendingPosts + $0.pendingRequests + $0.openReports } ?? 0
        for await _ in discussion.bus.signals(where: { _ in true }) {
            pendingTotal = (try? await discussion.indicators()).map { $0.pendingPosts + $0.pendingRequests + $0.openReports } ?? pendingTotal
        }
    }

    private func scheduleReload() {
        debounce?.cancel()
        debounce = Task {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func reload() {
        guard tab != .mine else { return }
        posts = discussion.pageFeed(tab: tab, sport: sport, forumId: forum?.id, search: query)
        generation += 1
    }

    /** 选的论坛收窄每个标签；名字另外取回来放在标签上。 */
    func pickForum(_ ids: Set<String>) async {
        pickerOpen = false
        guard let id = ids.first else {
            clearForum()
            return
        }
        forum = try? await discussion.forumsByIds([id]).first
        reload()
    }

    func clearForum() {
        forum = nil
        reload()
    }

    func toggleLike(_ post: PostCard) async {
        let liked = !post.likedByMe
        flip(post.id) { $0.likedByMe = liked; $0.likeCount = max(0, $0.likeCount + (liked ? 1 : -1)) }
        do {
            try await discussion.setPostLiked(post.id, liked)
        } catch {
            flip(post.id) { $0.likedByMe = !liked; $0.likeCount = max(0, $0.likeCount + (liked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    func toggleBookmark(_ post: PostCard) async {
        let bookmarked = !post.bookmarkedByMe
        flip(post.id) { $0.bookmarkedByMe = bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? 1 : -1)) }
        do {
            try await discussion.setPostBookmarked(post.id, bookmarked)
        } catch {
            flip(post.id) { $0.bookmarkedByMe = !bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    private func flip(_ id: String, _ change: (inout PostCard) -> Void) {
        posts.update(where: { $0.id == id }, change)
    }

    func submitReport(_ reason: ForumReportReason, _ detail: String) async {
        guard let post = reporting, let forumId = post.forums.first?.forumId else { return }
        reportBusy = true
        defer {
            reportBusy = false
            reporting = nil
        }
        do {
            _ = try await discussion.createReport(CreateReportRequest(forumId: forumId, postId: post.id, reason: reason, detail: detail))
            PulsoMessageCenter.shared.success("discussion_report_sent")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }
}

/** 论坛（Android `ForumFeedScreen`）：搜帖子 + 搜论坛 + 我的论坛，标签，运动筛选，帖子列表，右下角发帖。 */
struct ForumFeedView: View {
    @State private var model = ForumFeedModel()
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        List {
            Section {
                Picker(selection: $model.tab) {
                    ForEach(ForumFeedTab.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                if model.tab != .mine { filters }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if model.tab == .mine { mine } else { feed }
        }
        .listStyle(.plain)
        .searchable(text: $model.query, prompt: Text("discussion_search_posts_placeholder"))
        .navigationTitle("shell_dest_forum")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: LoopRoute.forumSearch) { Image(systemName: "magnifyingglass.circle") }
                    .accessibilityLabel(Text("discussion_search_forums"))
                NavigationLink(value: LoopRoute.myForums) {
                    Image(systemName: "text.bubble")
                        .overlay(alignment: .topTrailing) { if model.pendingTotal > 0 { Circle().fill(.red).frame(width: 8, height: 8).offset(x: 3, y: -3) } }
                }
                .accessibilityLabel(Text("discussion_my_forums"))
                NavigationLink(value: LoopRoute.likedPosts) { Image(systemName: "heart") }
                    .accessibilityLabel(Text("discussion_liked_title"))
                Button { model.pickerOpen = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .overlay(alignment: .topTrailing) { if model.forum != nil { Circle().fill(.tint).frame(width: 8, height: 8).offset(x: 3, y: -3) } }
                }
                .accessibilityLabel(Text("discussion_choose_forum"))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NavigationLink(value: LoopRoute.postCreate(prefill: PostCreatePrefill(forumId: model.forum?.id))) {
                Image(systemName: "square.and.pencil").font(.title2).padding(16)
            }
            .buttonStyle(.glassProminent)
            .clipShape(.circle)
            .padding(20)
            .accessibilityLabel(Text("discussion_new_post"))
        }
        .refreshable {
            if model.tab == .mine { await model.myPosts.refresh() } else { await model.posts.refresh() }
        }
        .task(id: model.generation) { await model.posts.observe() }
        .task { await model.myPosts.observe() }
        .task { await model.observeIndicators() }
        .sheet(isPresented: $model.pickerOpen) {
            ForumPickerSheet(selected: Set([model.forum?.id].compactMap { $0 }), max: 1) { ids in Task { await model.pickForum(ids) } }
        }
        .sheet(item: $model.reporting) { _ in
            ReportSheet(busy: model.reportBusy) { reason, detail in Task { await model.submitReport(reason, detail) } }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let forum = model.forum {
                    chip(Text(verbatim: forum.name), selected: true) { model.clearForum() }
                }
                chip(Text("discussion_all_sports"), selected: model.sport == nil) { model.sport = nil }
                ForEach(ForumSport.allCases, id: \.self) { sport in
                    chip(Text(sport.labelKey), selected: model.sport == sport) { model.sport = sport }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var feed: some View {
        let posts = model.posts
        if posts.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
        } else if let error = posts.error {
            PulsoLoadErrorView(error) { Task { await posts.refresh() } }.listRowBackground(Color.clear)
        } else if posts.isEmpty {
            ContentUnavailableView {
                Text(emptyTitle)
            } description: {
                Text((model.tab == .following ? "discussion_feed_empty_following_body" : "discussion_feed_empty_latest_body") as LocalizedStringKey)
            } actions: {
                if model.tab == .following {
                    NavigationLink("discussion_search_forums", value: LoopRoute.forumSearch).buttonStyle(.glassProminent)
                } else {
                    NavigationLink("discussion_new_post", value: LoopRoute.postCreate(prefill: PostCreatePrefill())).buttonStyle(.glassProminent)
                }
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(posts.items) { post in
                PostCardView(
                    post: post,
                    imageURL: model.imageURL,
                    onOpen: { shell?.push(LoopRoute.post(postId: post.id)) },
                    onLike: { Task { await model.toggleLike(post) } },
                    onBookmark: { Task { await model.toggleBookmark(post) } },
                    onRepost: { shell?.push(LoopRoute.postCreate(prefill: PostCreatePrefill(repostOfPostId: post.id))) },
                    onOpenForum: { shell?.push(LoopRoute.forum(forumId: $0)) },
                    onOpenAuthor: { shell?.push(LoopRoute.socialProfile(profileId: post.author.profileId)) },
                    onOpenTopic: { shell?.push(LoopRoute.forum(forumId: $0.forumId)) },
                    onReport: { model.reporting = post }
                )
                .onAppear { if post.id == posts.items.last?.id { posts.loadMore() } }
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch model.tab {
        case .following: "discussion_feed_empty_following"
        case .popular: "discussion_feed_empty_popular"
        default: "discussion_feed_empty_latest"
        }
    }

    @ViewBuilder
    private var mine: some View {
        let posts = model.myPosts
        if posts.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
        } else if let error = posts.error {
            PulsoLoadErrorView(error) { Task { await posts.refresh() } }.listRowBackground(Color.clear)
        } else if posts.isEmpty {
            ContentUnavailableView {
                Text("discussion_feed_empty_mine")
            } description: {
                Text("discussion_feed_empty_mine_body")
            } actions: {
                NavigationLink("discussion_new_post", value: LoopRoute.postCreate(prefill: PostCreatePrefill())).buttonStyle(.glassProminent)
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(posts.items) { post in
                PostCardView(
                    post: post,
                    imageURL: model.imageURL,
                    onOpen: { shell?.push(LoopRoute.post(postId: post.id)) },
                    onLike: {},
                    onBookmark: {},
                    status: post.status,
                    pinned: post.isPinned,
                    reason: post.rejectReason ?? post.removedReason
                )
                .onAppear { if post.id == posts.items.last?.id { posts.loadMore() } }
            }
        }
    }
}

