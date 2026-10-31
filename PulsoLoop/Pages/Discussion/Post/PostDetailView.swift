import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一条评论最多几个字。 */
let commentMax = 2000

/** 正在举报的：帖子本身或一条评论。 */
struct ReportTarget: Identifiable, Hashable {
    var commentId: String?
    var id: String { commentId ?? "post" }
}

/** 一篇帖子和它的评论（Android `PostDetailViewModel`）：赞和收藏先改；发评论后评论流重拉。 */
@MainActor
@Observable
final class PostDetailModel {
    let postId: String
    private(set) var post = Loadable<PostDetail>()
    var opOnly = false { didSet { if opOnly != oldValue { reloadComments() } } }
    var replyTo: PostComment?
    private(set) var posting = false
    var reporting: ReportTarget?
    private(set) var reportBusy = false
    private(set) var comments: PagedList<PostComment, String>
    private(set) var commentsGeneration = 0
    let linkCards = LinkCards()
    /** 打开的回复串，按顶层评论 id（没打开前收着）。 */
    private(set) var threads: [String: CommentThreadState] = [:]
    /** 我是否关注了作者；还不知道或者不提供（我自己的帖子、作者不是社区身份）时 nil。 */
    private(set) var followingAuthor: Bool?
    private(set) var followBusy = false

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored @Injected(\.socialService) private var social

    init(postId: String) {
        self.postId = postId
        comments = Container.shared.discussionService().pageComments(postId, opOnly: false)
    }

    var profileId: String { sessionStore.state.value.currentProfileId }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    func observe() async {
        await load()
        for await _ in discussion.bus.signals(where: { _ in true }) {
            await load()
        }
    }

    func load() async {
        post.isLoading = true
        do {
            let detail = try await discussion.post(postId)
            post = Loadable(data: detail, isLoading: false)
            for threadId in threads.keys { loadThread(threadId) }
            await loadFollow(detail)
        } catch {
            post = Loadable(data: post.data, isLoading: false, error: UiError(error))
        }
    }

    private func reloadComments() {
        comments = discussion.pageComments(postId, opOnly: opOnly)
        commentsGeneration += 1
    }

    func toggleLike() async {
        guard var data = post.data else { return }
        let before = data
        data.likedByMe.toggle()
        data.likeCount = max(0, data.likeCount + (data.likedByMe ? 1 : -1))
        post.data = data
        do {
            try await discussion.setPostLiked(postId, data.likedByMe)
        } catch {
            post.data = before
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    func toggleBookmark() async {
        guard var data = post.data else { return }
        let before = data
        data.bookmarkedByMe.toggle()
        data.bookmarkCount = max(0, data.bookmarkCount + (data.bookmarkedByMe ? 1 : -1))
        post.data = data
        do {
            try await discussion.setPostBookmarked(postId, data.bookmarkedByMe)
        } catch {
            post.data = before
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    /** 问一下我是否关注了别人帖子的社区作者；只有这时才显示关注按钮。 */
    private func loadFollow(_ detail: PostDetail) async {
        let session = sessionStore.state.value
        guard !detail.isAuthor, detail.author.profileScope == .community, session.isAuthValid else { return }
        let target = SocialTargetProfile(targetProfileId: detail.author.profileId, targetProfileScope: .community)
        if let relations = try? await social.getRelations(RelationStatusKey(accountId: session.currentAccountId, profileId: session.currentProfileId, targets: [target])) {
            followingAuthor = relations.items.first?.isFollowing ?? false
        }
    }

    func toggleFollowAuthor() async {
        guard let detail = post.data, let following = followingAuthor, !followBusy else { return }
        followBusy = true
        defer { followBusy = false }
        do {
            if following { try await social.unfollow(detail.author.profileId) } else { try await social.follow(detail.author.profileId) }
            followingAuthor = !following
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_follow_author_failed")
        }
    }

    /** 打开或收起一条顶层评论下面的回复。 */
    func toggleThread(_ threadId: String) {
        if threads[threadId] != nil { threads[threadId] = nil } else { loadThread(threadId) }
    }

    func moreReplies(_ threadId: String) {
        guard let thread = threads[threadId], let cursor = thread.nextCursor, !thread.loading else { return }
        loadThread(threadId, after: cursor)
    }

    private func loadThread(_ threadId: String, after: String = "") {
        threads[threadId] = (threads[threadId] ?? CommentThreadState()).with(loading: true)
        let discussion = discussion
        let postId = postId
        Task {
            do {
                let page = try await discussion.threadReplies(postId, threadCommentId: threadId, after: after)
                // 加载中被收起：保持收起。
                guard let current = threads[threadId] else { return }
                let replies = after.isEmpty ? page.items : current.replies + page.items
                threads[threadId] = CommentThreadState(replies: replies, nextCursor: page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }, loading: false)
            } catch {
                threads[threadId] = threads[threadId]?.with(loading: false)
                PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
            }
        }
    }

    /** 评论的赞 / 收藏同时改列表和打开的回复串里的那一条。 */
    private func updateComment(_ id: String, _ change: (inout PostComment) -> Void) {
        comments.update(where: { $0.id == id }, change)
        for (threadId, thread) in threads {
            guard let index = thread.replies.firstIndex(where: { $0.id == id }) else { continue }
            var replies = thread.replies
            change(&replies[index])
            threads[threadId] = CommentThreadState(replies: replies, nextCursor: thread.nextCursor, loading: thread.loading)
        }
    }

    func toggleCommentLike(_ comment: PostComment) async {
        let liked = !comment.likedByMe
        updateComment(comment.id) { $0.likedByMe = liked; $0.likeCount = max(0, $0.likeCount + (liked ? 1 : -1)) }
        do {
            try await discussion.setCommentLiked(comment.id, liked)
        } catch {
            updateComment(comment.id) { $0.likedByMe = !liked; $0.likeCount = max(0, $0.likeCount + (liked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    func toggleCommentBookmark(_ comment: PostComment) async {
        let bookmarked = !comment.bookmarkedByMe
        updateComment(comment.id) { $0.bookmarkedByMe = bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? 1 : -1)) }
        do {
            try await discussion.setCommentBookmarked(comment.id, bookmarked)
        } catch {
            updateComment(comment.id) { $0.bookmarkedByMe = !bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    /** 发评论；成功返回 true（输入框清空）。 */
    func comment(html: String, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= commentMax, !posting else { return false }
        posting = true
        defer { posting = false }
        do {
            _ = try await discussion.createComment(postId, contentHtml: html, replyToCommentId: replyTo?.id)
            // 回复落在这一串里：打开它，写的人能看到。
            if let reply = replyTo {
                let threadId = reply.threadCommentId ?? reply.id
                if threads[threadId] == nil { loadThread(threadId) }
            }
            replyTo = nil
            return true
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
            return false
        }
    }

    func deleteComment(_ comment: PostComment) async {
        do { try await discussion.deleteComment(comment.id) } catch { PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed") }
    }

    func deletePost() async -> Bool {
        do {
            try await discussion.deletePost(postId)
            PulsoMessageCenter.shared.success("discussion_post_deleted")
            return true
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
            return false
        }
    }

    func submitReport(_ reason: ForumReportReason, _ detail: String) async {
        guard let target = reporting, let forumId = post.data?.reportForumId else { return }
        reportBusy = true
        defer {
            reportBusy = false
            reporting = nil
        }
        do {
            _ = try await discussion.createReport(CreateReportRequest(
                forumId: forumId, postId: target.commentId == nil ? postId : nil, commentId: target.commentId, reason: reason, detail: detail
            ))
            PulsoMessageCenter.shared.success("discussion_report_sent")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }
}

/**
 * 帖子详情（Android `PostDetailScreen`）：作者、标题、正文段落（文字 / 整宽照片 / 链接卡片）、没放进正文的照片、
 * 话题、转发、操作栏、发在哪些论坛；评论（只看楼主、回复、举报、删除），底部写评论。
 */
struct PostDetailView: View {
    @State private var model: PostDetailModel
    @State private var draft = AttributedString()
    @State private var confirmingDelete = false
    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulsoPalette) private var palette

    init(postId: String) {
        _model = State(initialValue: PostDetailModel(postId: postId))
    }

    var body: some View {
        Group {
            if let data = model.post.data {
                content(data)
            } else if let error = model.post.error {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("discussion_post_title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .task(id: model.commentsGeneration) { await model.comments.observe() }
        .sheet(item: $model.reporting) { _ in
            ReportSheet(busy: model.reportBusy) { reason, detail in Task { await model.submitReport(reason, detail) } }
        }
        .sheet(isPresented: $confirmingDelete) {
            VStack(alignment: .leading, spacing: 16) {
                Text("discussion_delete_post_title").font(.title3.bold())
                Text("discussion_delete_post_body").foregroundStyle(.secondary)
                PulsoHoldButton("discussion_action_delete") {
                    Task {
                        if await model.deletePost() {
                            confirmingDelete = false
                            dismiss()
                        }
                    }
                }
            }
            .padding(24)
            .presentationDetents([.height(240)])
        }
    }

    private func content(_ data: PostDetail) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AuthorLine(author: data.author, at: data.firstPublishedAt ?? data.createdAt, avatarURL: model.imageURL(data.author.avatarImageId)) {
                        shell?.push(LoopRoute.socialProfile(profileId: data.author.profileId))
                    }
                    if let following = model.followingAuthor {
                        Button { Task { await model.toggleFollowAuthor() } } label: {
                            PulsoButtonLabel((following ? "discussion_following_author" : "discussion_follow_author") as LocalizedStringKey, loading: model.followBusy)
                        }
                        // 已关注是灰色柔和，没关注是强调色柔和（Android 作者行右边的小按钮）。
                        .buttonStyle(.pulso(.soft, tone: following ? .gray : .accent, size: .small))
                        .disabled(model.followBusy)
                    }
                }
                Text(verbatim: data.title).font(.title2.bold())
                if let edited = data.editedAt {
                    Text(verbatim: localizedFormat("discussion_edited_at", DateTimeFormatters.monthDayTime(edited) ?? "")).font(.caption2).foregroundStyle(.secondary)
                }
                sections(data.sections)
                // 正文里没放的照片，按张数排：一张宽图、两张并排、一张高的配两张、2×2 带「+N」。
                let gallery = unplacedImages(data).map(\.imageId)
                PostPhotos(layout: detailPhotoLayout(postId: data.id, count: gallery.count), previewIds: Array(gallery.prefix(4)), imageCount: gallery.count, imageURL: model.imageURL)
                if !data.topics.isEmpty {
                    TopicChipRow(topics: data.topics) { shell?.push(LoopRoute.forum(forumId: $0.forumId)) }
                }
                if let repost = data.repostOf {
                    RepostQuote(repost: repost).onTapGesture { if repost.available { shell?.push(LoopRoute.post(postId: repost.postId)) } }
                }
                PostActionBar(
                    likedByMe: data.likedByMe, likeCount: data.likeCount, commentCount: data.commentCount, repostCount: data.repostCount,
                    bookmarkedByMe: data.bookmarkedByMe,
                    onLike: { Task { await model.toggleLike() } },
                    onComment: {},
                    onRepost: data.allowReposts ? { shell?.push(LoopRoute.postCreate(prefill: PostCreatePrefill(repostOfPostId: data.id))) } : nil,
                    shareURL: data.live.contains { $0.allowShares } ? postShareURL(data.id) : nil,
                    onBookmark: { Task { await model.toggleBookmark() } }
                )
            }
            // 正文直接铺在页面上，不套卡片（Android 帖子页）。
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            if !data.publications.isEmpty {
                Section("discussion_published_in") {
                    ForEach(data.publications, id: \.forumId) { publication in
                        Button { shell?.push(LoopRoute.forum(forumId: publication.forumId)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(verbatim: publication.forumName)
                                    if publication.status != .published || data.isAuthor { PostStatusChip(status: publication.status) }
                                }
                                if data.isAuthor, let reason = publication.rejectReason ?? publication.removedReason, !reason.isEmpty {
                                    Text(verbatim: reason).font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            commentsSection(data)
        }
        .safeAreaInset(edge: .bottom) { if data.allowComments { composer } }
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if data.isAuthor {
                        NavigationLink(value: LoopRoute.postEdit(postId: data.id)) { Label("discussion_action_edit", systemImage: "pencil") }
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("discussion_action_delete", systemImage: "trash") }
                    } else if data.reportForumId != nil {
                        Button { model.reporting = ReportTarget() } label: { Label("discussion_action_report", systemImage: "flag") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(Text("discussion_more"))
            }
        }
    }

    /**
     * 正文按写的顺序：文字、段落之间的照片、链接——一个活动或场馆是大卡片，一篇帖子或一栋建筑是一行，
     * 连着的几个链接合成一组「相关内容」。
     */
    @ViewBuilder
    private func sections(_ sections: [PostSection]) -> some View {
        ForEach(Array(bodyBlocks(sections).enumerated()), id: \.offset) { _, block in
            switch block {
            case let .links(links) where links.count > 1:
                PostLinkGroup(links: links, cards: model.linkCards, imageURL: model.imageURL, onOpen: { open($0) }, title: "discussion_card_related", limit: links.count)
            case let .links(links):
                if let link = links.first {
                    LinkTargetCard(
                        link: link,
                        state: model.linkCards.states[link.key] ?? .loading,
                        variant: link.type == .event || link.type == .venue ? .hero : .row,
                        imageURL: model.imageURL,
                        onOpen: { open(link) },
                        label: link.type == .post ? String(localized: "discussion_card_linked_post") : nil
                    )
                    .onAppear { model.linkCards.ensure(link) }
                }
            case let .text(html):
                RichTextBody(html: html)
            case let .image(imageId):
                PulsoRemoteImage(url: model.imageURL(imageId))
                    .aspectRatio(3 / 2, contentMode: .fill)
                    .frame(width: 208)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func open(_ link: PostLink) {
        if let route = PostLinkLoader.route(link) { shell?.push(route) }
    }

    /** 没被正文段落放进去的照片：正文下面一排。 */
    private func unplacedImages(_ data: PostDetail) -> [PostImage] {
        let placed = Set(data.sections.compactMap { section -> String? in
            if case let .imageSection(image) = section { return image.imageId }
            return nil
        })
        return data.images.sorted { $0.sortOrder < $1.sortOrder }.filter { !placed.contains($0.imageId) }
    }

    @ViewBuilder
    private func commentsSection(_ data: PostDetail) -> some View {
        let comments = model.comments
        Section {
            if comments.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = comments.error {
                PulsoErrorBanner(error) { Task { await comments.refresh() } }
            } else if comments.items.isEmpty {
                Text("discussion_comments_empty").foregroundStyle(.secondary)
            } else {
                ForEach(comments.items, id: \.id) { comment in
                    commentRow(comment, data: data, showQuote: true)
                    // 只看楼主时是一个平的列表，每条回复带引用；否则顶层评论下面可以展开回复。
                    if !model.opOnly, comment.threadReplyCount > 0 {
                        thread(comment, data: data)
                    }
                }
            }
        } header: {
            HStack {
                Text(verbatim: localizedFormat("discussion_comments_count", data.commentCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .textCase(nil)
                Spacer()
                Toggle("discussion_op_only", isOn: $model.opOnly).fixedSize().font(.caption).tint(palette.accent.step(9))
            }
        }
    }

    private func commentRow(_ comment: PostComment, data: PostDetail, showQuote: Bool) -> some View {
        CommentRowView(
            comment: comment,
            avatarURL: model.imageURL(comment.author.avatarImageId),
            onLike: { Task { await model.toggleCommentLike(comment) } },
            onBookmark: { Task { await model.toggleCommentBookmark(comment) } },
            onReply: data.allowComments ? { model.replyTo = comment } : nil,
            onReport: comment.author.profileId != model.profileId && data.reportForumId != nil ? { model.reporting = ReportTarget(commentId: comment.id) } : nil,
            onDelete: comment.author.profileId == model.profileId || data.isAuthor ? { Task { await model.deleteComment(comment) } } : nil,
            onOpenAuthor: { shell?.push(LoopRoute.socialProfile(profileId: comment.author.profileId)) },
            showQuote: showQuote
        )
        .onAppear { if comment.id == model.comments.items.last?.id { model.comments.loadMore() } }
    }

    /** 顶层评论下面的回复：收在「展开 N 条回复」后面，打开后缩进一层。回复顶层评论的不带引用，回复回复的显示它回的那条。 */
    @ViewBuilder
    private func thread(_ comment: PostComment, data: PostDetail) -> some View {
        let thread = model.threads[comment.id]
        Button { model.toggleThread(comment.id) } label: {
            Label {
                Text(verbatim: thread != nil ? String(localized: "discussion_hide_replies") : localizedFormat("discussion_show_replies", comment.threadReplyCount))
            } icon: {
                Image(systemName: thread != nil ? "chevron.up" : "chevron.down")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.accent.step(11))
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
        if let thread {
            ForEach(thread.replies, id: \.id) { reply in
                commentRow(reply, data: data, showQuote: reply.replyTo?.commentId != reply.threadCommentId)
                    .padding(.leading, 32)
            }
            if thread.loading {
                ProgressView().padding(.leading, 32)
            } else if thread.nextCursor != nil {
                Button("discussion_more_replies") { model.moreReplies(comment.id) }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .padding(.leading, 32)
            }
        }
    }

    /** 底部写评论：回复谁、编辑器、发送。 */
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply = model.replyTo {
                HStack {
                    Text(verbatim: localizedFormat("discussion_replying_to", reply.author.displayName ?? "")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("discussion_cancel") { model.replyTo = nil }.font(.caption)
                }
            }
            HStack(alignment: .bottom) {
                RichTextEditor(text: $draft, placeholder: "discussion_comment_placeholder", maxChars: commentMax, showCounter: false, compact: true)
                Button("discussion_comment_send") {
                    let html = RichTextHTML.html(draft, context: fontContext)
                    let text = String(draft.characters)
                    Task { if await model.comment(html: html, text: text) { draft = AttributedString() } }
                }
                .buttonStyle(.pulso())
                .disabled(model.posting || String(draft.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(PulsoSpace.s3)
        .background(palette.background.shadow(.drop(color: .black.opacity(0.08), radius: 4, y: -1)))
    }
}

extension PostComment: Identifiable {}

/** 打开的一串回复，最早的在前；读完了 [nextCursor] 是 nil。 */
struct CommentThreadState: Hashable {
    var replies: [PostComment] = []
    var nextCursor: String?
    var loading = true

    func with(loading: Bool) -> CommentThreadState {
        CommentThreadState(replies: replies, nextCursor: nextCursor, loading: loading)
    }
}

/** 正文的一段：一个段落，或连着的几个链接段落（读起来是一组「相关内容」）。 */
private enum BodyBlock {
    case text(String)
    case image(String)
    case links([PostLink])
}

private func bodyBlocks(_ sections: [PostSection]) -> [BodyBlock] {
    var blocks: [BodyBlock] = []
    for section in sections {
        switch section {
        case let .textSection(text):
            blocks.append(.text(text.contentHtml))
        case let .imageSection(image):
            blocks.append(.image(image.imageId))
        case let .linkSection(link):
            if case let .links(previous) = blocks.last {
                blocks[blocks.count - 1] = .links(previous + [link.link])
            } else {
                blocks.append(.links([link.link]))
            }
        }
    }
    return blocks
}
