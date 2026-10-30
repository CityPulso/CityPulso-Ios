import PulsoLinkCore

/** 论坛门面（Android `DiscussionService`）：分页 + 写操作；每次写操作后经 [DiscussionEventBus] 让所有论坛列表重拉。 */
struct DiscussionService: Sendable {
    let repository: DiscussionRepository
    let bus: DiscussionEventBus

    private var invalidates: @Sendable () -> AsyncStream<Void> {
        let bus = bus
        return { bus.signals { _ in true } }
    }

    func invalidate() {
        bus.invalidate()
    }

    func indicators() async throws -> DiscussionIndicators { try await repository.indicators() }

    /* ------------------------------ forums ------------------------------ */

    @MainActor
    func pageForums(_ filter: ListForumsRequest) -> PagedList<ForumItem, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in
            var page = filter
            page.offset = offset
            page.limit = limit
            return try await repository.listForums(page)
        }
    }

    /** 一页、不分页：选择器和短列表。 */
    func listForums(_ filter: ListForumsRequest) async throws -> ListWithTotal<ForumItem> { try await repository.listForums(filter) }

    func forumsByIds(_ ids: [String]) async throws -> [ForumItem] { ids.isEmpty ? [] : try await repository.forumsByIds(ids) }

    @MainActor
    func pageMyForums() -> PagedList<MyForum, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.myForums(offset: offset, limit: limit) }
    }

    @MainActor
    func pageFavoriteForums(_ search: String?) -> PagedList<ForumFavorite, Int> {
        let repository = repository
        let search = search.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return .offset(invalidates: invalidates) { offset, limit in try await repository.favoriteForums(offset: offset, limit: limit, search: search) }
    }

    func venueStaff(_ search: String?) async throws -> [ForumVenueStaff] {
        try await repository.venueStaff(search: search.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    func createForum(_ body: CreateForumRequest) async throws -> String { try await mutate { try await repository.createForum(body) } }
    func forum(_ id: String) async throws -> ForumDetail { try await repository.forum(id) }
    func patchForum(_ id: String, _ body: PatchForumRequest) async throws { try await mutate { try await repository.patchForum(id, body) } }

    /** 整组背景图替换（1 到 FORUM_BACKGROUNDS_MAX 张，第一张是封面）。 */
    func replaceBackgrounds(_ id: String, _ backgrounds: [ForumImageInput]) async throws { try await mutate { try await repository.replaceBackgrounds(id, backgrounds) } }

    func archiveForum(_ id: String) async throws { try await mutate { try await repository.archiveForum(id) } }
    func reopenForum(_ id: String) async throws { try await mutate { try await repository.reopenForum(id) } }
    func deleteForum(_ id: String) async throws { try await mutate { try await repository.deleteForum(id) } }

    /** 关注 = 收藏：论坛进「我关注的论坛」，它的帖子进关注流。 */
    func setForumFavorite(_ id: String, _ favorite: Bool) async throws { try await mutate { try await repository.setForumFavorite(id, favorite) } }

    /* ------------------------------ staff ------------------------------ */

    func applyToForum(_ id: String, message: String) async throws { try await mutate { try await repository.applyToForum(id, message: message) } }

    @MainActor
    func pageJoinRequests(_ id: String) -> PagedList<ForumMember, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.joinRequests(id, offset: offset, limit: limit) }
    }

    @MainActor
    func pageStaff(_ id: String) -> PagedList<ForumMember, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.staff(id, offset: offset, limit: limit) }
    }

    func approveJoinRequest(_ id: String, memberId: String, role: ForumMemberRole) async throws { try await mutate { try await repository.approveJoinRequest(id, memberId: memberId, role: role) } }
    func rejectJoinRequest(_ id: String, memberId: String, reason: String?) async throws { try await mutate { try await repository.rejectJoinRequest(id, memberId: memberId, reason: reason) } }
    func changeMemberRole(_ id: String, memberId: String, role: ForumMemberRole) async throws { try await mutate { try await repository.changeMemberRole(id, memberId: memberId, role: role) } }
    func removeMember(_ id: String, memberId: String) async throws { try await mutate { try await repository.removeMember(id, memberId: memberId) } }
    func leaveForum(_ id: String) async throws { try await mutate { try await repository.leaveForum(id) } }

    /* ------------------------------ topics ------------------------------ */

    func topics(_ id: String) async throws -> [ForumTopic] { try await repository.topics(id) }

    /** 帖子里关联的活动，按帖子新旧（分页）。 */
    @MainActor
    func pageForumEvents(_ id: String) -> PagedList<ForumEvent, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.forumEvents(id, offset: offset, limit: limit) }
    }

    func createTopic(_ id: String, name: String) async throws -> String {
        try await mutate { try await repository.createTopic(id, name: name.trimmingCharacters(in: .whitespaces)) }
    }

    func renameTopic(_ topicId: String, name: String) async throws {
        try await mutate { try await repository.patchTopic(topicId, PatchTopicRequest(name: name.trimmingCharacters(in: .whitespaces))) }
    }

    func moveTopic(_ topicId: String, sortOrder: Int) async throws { try await mutate { try await repository.patchTopic(topicId, PatchTopicRequest(sortOrder: sortOrder)) } }
    func deleteTopic(_ topicId: String) async throws { try await mutate { try await repository.deleteTopic(topicId) } }

    /** 替换帖子在一个论坛里的话题（作者或那个论坛的管理员）。 */
    func setPostTopics(forumId: String, postId: String, topicIds: [String]) async throws {
        try await mutate { try await repository.setPostTopics(forumId: forumId, postId: postId, topicIds: topicIds) }
    }

    /* ------------------------------ announcements ------------------------------ */

    func announcements(_ id: String) async throws -> [ForumAnnouncement] { try await repository.announcements(id) }
    func createAnnouncement(_ id: String, _ body: CreateAnnouncementRequest) async throws -> String { try await mutate { try await repository.createAnnouncement(id, body) } }
    func patchAnnouncement(_ announcementId: String, _ body: PatchAnnouncementRequest) async throws { try await mutate { try await repository.patchAnnouncement(announcementId, body) } }
    func deleteAnnouncement(_ announcementId: String) async throws { try await mutate { try await repository.deleteAnnouncement(announcementId) } }

    /* ------------------------------ posts ------------------------------ */

    /** 首页信息流（游标）；「我的」标签是 [pageMyPosts]。 */
    @MainActor
    func pageFeed(tab: ForumFeedTab, sport: ForumSport?, forumId: String?, search: String? = nil, topicId: String? = nil, kind: PostKind? = nil) -> PagedList<PostCard, String> {
        let repository = repository
        let search = search?.trimmingCharacters(in: .whitespaces)
        return .cursor(invalidates: invalidates) { after, limit in
            try await repository.feed(FeedRequest(
                tab: tab.rawValue, after: after, limit: limit, sport: sport, forumId: forumId, topicId: topicId, kind: kind,
                search: (search?.isEmpty ?? true) ? nil : search
            ))
        }
    }

    /** 一个论坛的帖子流（可以只看一个话题）；置顶的排在第一页最前面。 */
    @MainActor
    func pageForumPosts(_ id: String, topicId: String? = nil) -> PagedList<ForumPost, String> {
        let repository = repository
        return .cursor(invalidates: invalidates) { after, limit in
            let page = try await repository.forumStream(id, after: after, limit: limit, topicId: topicId)
            return ListWithNextCursor(items: after.isEmpty ? page.pinned + page.items : page.items, nextCursor: page.nextCursor)
        }
    }

    @MainActor
    func pagePendingPosts(_ id: String) -> PagedList<ForumPost, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.pendingPosts(id, offset: offset, limit: limit) }
    }

    @MainActor
    func pageMyPosts() -> PagedList<ForumPost, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.myPosts(offset: offset, limit: limit) }
    }

    @MainActor
    func pageLikedPosts() -> PagedList<PostCard, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.likedPosts(offset: offset, limit: limit) }
    }

    @MainActor
    func pageBookmarkedPosts() -> PagedList<PostCard, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.bookmarkedPosts(offset: offset, limit: limit) }
    }

    func approvePost(_ id: String, postId: String) async throws { try await mutate { try await repository.approvePost(id, postId: postId) } }
    func rejectPost(_ id: String, postId: String, reason: String?) async throws { try await mutate { try await repository.rejectPost(id, postId: postId, reason: reason) } }
    func removePost(_ id: String, postId: String, reason: String?) async throws { try await mutate { try await repository.removePost(id, postId: postId, reason: reason) } }
    func setPostPinned(_ id: String, postId: String, pinned: Bool) async throws { try await mutate { try await repository.setPostPinned(id, postId: postId, pinned: pinned) } }
    func createPost(_ body: CreatePostRequest) async throws -> PostCreated { try await mutate { try await repository.createPost(body) } }
    func post(_ id: String) async throws -> PostDetail { try await repository.post(id) }
    func patchPost(_ id: String, _ body: PatchPostRequest) async throws -> PostPatched { try await mutate { try await repository.patchPost(id, body) } }
    func deletePost(_ id: String) async throws { try await mutate { try await repository.deletePost(id) } }

    func publishPost(_ id: String, publications: [PublicationInput]) async throws -> PostPatched {
        try await mutate { try await repository.publishPost(id, publications: publications) }
    }

    /** 点赞和收藏由调用方先改；服务端不同意时才发失效。 */
    func setPostLiked(_ id: String, _ liked: Bool) async throws { try await repository.setPostLiked(id, liked) }
    func setPostBookmarked(_ id: String, _ bookmarked: Bool) async throws { try await repository.setPostBookmarked(id, bookmarked) }

    /* ------------------------------ comments ------------------------------ */

    @MainActor
    func pageComments(_ postId: String, opOnly: Bool) -> PagedList<PostComment, String> {
        let repository = repository
        return .cursor(invalidates: invalidates) { after, limit in try await repository.comments(postId, after: after, limit: limit, opOnly: opOnly) }
    }

    /** 打开一串回复时每页读几条。 */
    static let threadPageSize = 20

    func threadReplies(_ postId: String, threadCommentId: String, after: String) async throws -> ListWithNextCursor<PostComment> {
        try await repository.threadReplies(postId, threadCommentId: threadCommentId, after: after, limit: Self.threadPageSize)
    }

    func createComment(_ postId: String, contentHtml: String, replyToCommentId: String?) async throws -> String {
        try await mutate { try await repository.createComment(postId, contentHtml: contentHtml, replyToCommentId: replyToCommentId) }
    }

    func deleteComment(_ commentId: String) async throws { try await mutate { try await repository.deleteComment(commentId) } }
    func setCommentLiked(_ commentId: String, _ liked: Bool) async throws { try await repository.setCommentLiked(commentId, liked) }
    func setCommentBookmarked(_ commentId: String, _ bookmarked: Bool) async throws { try await repository.setCommentBookmarked(commentId, bookmarked) }

    @MainActor
    func pageBookmarkedComments() -> PagedList<CommentBookmark, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.bookmarkedComments(offset: offset, limit: limit) }
    }

    /* ------------------------------ reports ------------------------------ */

    func createReport(_ body: CreateReportRequest) async throws -> String { try await repository.createReport(body) }

    @MainActor
    func pageReports(_ id: String, status: ForumReportStatus?) -> PagedList<ForumReport, Int> {
        let repository = repository
        return .offset(invalidates: invalidates) { offset, limit in try await repository.reports(id, offset: offset, limit: limit, status: status) }
    }

    func resolveReport(_ reportId: String, action: ForumReportAction, note: String) async throws {
        try await mutate { try await repository.resolveReport(reportId, action: action, note: note) }
    }

    func dismissReport(_ reportId: String, note: String) async throws { try await mutate { try await repository.dismissReport(reportId, note: note) } }

    private func mutate<T>(_ block: () async throws -> T) async throws -> T {
        let out = try await block()
        bus.invalidate()
        return out
    }
}
