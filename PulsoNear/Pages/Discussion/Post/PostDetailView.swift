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

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

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
            post = try await Loadable(data: discussion.post(postId), isLoading: false)
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

    func toggleCommentLike(_ comment: PostComment) async {
        let liked = !comment.likedByMe
        comments.update(where: { $0.id == comment.id }) { $0.likedByMe = liked; $0.likeCount = max(0, $0.likeCount + (liked ? 1 : -1)) }
        do {
            try await discussion.setCommentLiked(comment.id, liked)
        } catch {
            comments.update(where: { $0.id == comment.id }) { $0.likedByMe = !liked; $0.likeCount = max(0, $0.likeCount + (liked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    func toggleCommentBookmark(_ comment: PostComment) async {
        let bookmarked = !comment.bookmarkedByMe
        comments.update(where: { $0.id == comment.id }) { $0.bookmarkedByMe = bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? 1 : -1)) }
        do {
            try await discussion.setCommentBookmarked(comment.id, bookmarked)
        } catch {
            comments.update(where: { $0.id == comment.id }) { $0.bookmarkedByMe = !bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? -1 : 1)) }
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
                AuthorLine(author: data.author, at: data.firstPublishedAt ?? data.createdAt, avatarURL: model.imageURL(data.author.avatarImageId)) {
                    shell?.push(NearRoute.socialProfile(profileId: data.author.profileId))
                }
                HStack(alignment: .top) {
                    Text(verbatim: data.title).font(.title2.bold())
                    Spacer(minLength: 0)
                    PostKindChip(kind: data.kind)
                }
                if let edited = data.editedAt {
                    Text(verbatim: localizedFormat("discussion_edited_at", DateTimeFormatters.monthDayTime(edited) ?? "")).font(.caption2).foregroundStyle(.secondary)
                }
                sections(data.sections)
                let gallery = unplacedImages(data)
                if !gallery.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(gallery, id: \.id) { image in
                                PulsoRemoteImage(url: model.imageURL(image.imageId)).frame(width: 120, height: 120).clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                }
                if !data.topics.isEmpty {
                    TopicChipRow(topics: data.topics) { shell?.push(NearRoute.forum(forumId: $0.forumId)) }
                }
                if let repost = data.repostOf {
                    RepostQuote(repost: repost).onTapGesture { if repost.available { shell?.push(NearRoute.post(postId: repost.postId)) } }
                }
                PostActionBar(
                    likedByMe: data.likedByMe, likeCount: data.likeCount, commentCount: data.commentCount, repostCount: data.repostCount,
                    bookmarkedByMe: data.bookmarkedByMe,
                    onLike: { Task { await model.toggleLike() } },
                    onComment: {},
                    onRepost: data.allowReposts ? { shell?.push(NearRoute.postCreate(prefill: PostCreatePrefill(repostOfPostId: data.id))) } : nil,
                    shareURL: data.live.contains { $0.allowShares } ? postShareURL(data.id) : nil,
                    onBookmark: { Task { await model.toggleBookmark() } }
                )
            }
            if !data.publications.isEmpty {
                Section("discussion_published_in") {
                    ForEach(data.publications, id: \.forumId) { publication in
                        Button { shell?.push(NearRoute.forum(forumId: publication.forumId)) } label: {
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
                        NavigationLink(value: NearRoute.postEdit(postId: data.id)) { Label("discussion_action_edit", systemImage: "pencil") }
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("discussion_action_delete", systemImage: "trash") }
                    } else if data.reportForumId != nil {
                        Button { model.reporting = ReportTarget() } label: { Label("discussion_action_report", systemImage: "flag") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("discussion_more"))
            }
        }
    }

    /** 正文段落（文字、整宽照片、链接卡片），段与段之间空一行。 */
    @ViewBuilder
    private func sections(_ sections: [PostSection]) -> some View {
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
            switch section {
            case let .textSection(text):
                RichTextBody(html: text.contentHtml)
            case let .imageSection(image):
                PulsoRemoteImage(url: model.imageURL(image.imageId), contentMode: .fit).frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: 8))
            case let .linkSection(link):
                Button {
                    if let route = PostLinkLoader.route(link.link) { shell?.push(route) }
                } label: {
                    PostLinkCard(link: link.link, state: model.linkCards.states[link.link.key] ?? .loading, imageURL: model.imageURL)
                }
                .buttonStyle(.plain)
                .onAppear { model.linkCards.ensure(link.link) }
            }
        }
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
                    CommentRowView(
                        comment: comment,
                        avatarURL: model.imageURL(comment.author.avatarImageId),
                        onLike: { Task { await model.toggleCommentLike(comment) } },
                        onBookmark: { Task { await model.toggleCommentBookmark(comment) } },
                        onReply: data.allowComments ? { model.replyTo = comment } : nil,
                        onReport: comment.author.profileId != model.profileId && data.reportForumId != nil ? { model.reporting = ReportTarget(commentId: comment.id) } : nil,
                        onDelete: comment.author.profileId == model.profileId || data.isAuthor ? { Task { await model.deleteComment(comment) } } : nil,
                        onOpenAuthor: { shell?.push(NearRoute.socialProfile(profileId: comment.author.profileId)) }
                    )
                    .onAppear { if comment.id == comments.items.last?.id { comments.loadMore() } }
                }
            }
        } header: {
            HStack {
                Text(verbatim: localizedFormat("discussion_comments_count", data.commentCount))
                Spacer()
                Toggle("discussion_op_only", isOn: $model.opOnly).fixedSize().font(.caption)
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
                RichTextEditor(text: $draft, placeholder: "discussion_comment_placeholder", maxChars: commentMax, minHeight: 44, showCounter: false)
                    .frame(maxHeight: 160)
                Button("discussion_comment_send") {
                    let html = RichTextHTML.html(draft, context: fontContext)
                    let text = String(draft.characters)
                    Task { if await model.comment(html: html, text: text) { draft = AttributedString() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.posting || String(draft.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(.bar)
    }
}

extension PostComment: Identifiable {}
