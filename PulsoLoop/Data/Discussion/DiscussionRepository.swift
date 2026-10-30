import PulsoLinkCore

/** 论坛仓储（Android `DiscussionRepository`）：一次调用一个端点。 */
struct DiscussionRepository: Sendable {
    let api: DiscussionAPI

    func indicators() async throws -> DiscussionIndicators { try await api.indicators().dataOrThrow("DiscussionIndicators") }
    func listForums(_ body: ListForumsRequest) async throws -> ListWithTotal<ForumItem> { try await api.listForums(body).dataOrThrow("ListForums") }
    func forumsByIds(_ ids: [String]) async throws -> [ForumItem] { try await api.forumsByIds(DiscussionIdsRequest(ids: ids)).dataOrThrow("ListForumsByIds") }

    func myForums(offset: Int, limit: Int) async throws -> ListWithTotal<MyForum> {
        try await api.myForums(DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListMyForums")
    }

    func favoriteForums(offset: Int, limit: Int, search: String?) async throws -> ListWithTotal<ForumFavorite> {
        try await api.favoriteForums(DiscussionPageRequest(offset: offset, limit: limit, search: search)).dataOrThrow("ListFavoriteForums")
    }

    func venueStaff(search: String?) async throws -> [ForumVenueStaff] { try await api.venueStaff(search: search).dataOrThrow("ListForumVenueStaff") }
    func createForum(_ body: CreateForumRequest) async throws -> String { try await api.createForum(body).dataOrThrow("CreateForum").id }
    func forum(_ id: String) async throws -> ForumDetail { try await api.forum(id: id).dataOrThrow("GetForum") }
    func patchForum(_ id: String, _ body: PatchForumRequest) async throws { try await api.patchForum(id: id, body) }

    func replaceBackgrounds(_ id: String, _ backgrounds: [ForumImageInput]) async throws {
        try await api.replaceBackgrounds(id: id, ReplaceBackgroundsRequest(backgrounds: backgrounds))
    }

    func archiveForum(_ id: String) async throws { try await api.archiveForum(id: id) }
    func reopenForum(_ id: String) async throws { try await api.reopenForum(id: id) }
    func deleteForum(_ id: String) async throws { try await api.deleteForum(id: id) }

    func setForumFavorite(_ id: String, _ favorite: Bool) async throws {
        if favorite { try await api.favoriteForum(id: id) } else { try await api.unfavoriteForum(id: id) }
    }

    func applyToForum(_ id: String, message: String) async throws { try await api.applyToForum(id: id, JoinForumRequest(message: message)) }

    func joinRequests(_ id: String, offset: Int, limit: Int) async throws -> ListWithTotal<ForumMember> {
        try await api.joinRequests(id: id, DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListForumJoinRequests")
    }

    func approveJoinRequest(_ id: String, memberId: String, role: ForumMemberRole) async throws {
        try await api.approveJoinRequest(id: id, memberId: memberId, DecideMemberRequest(role: role))
    }

    func rejectJoinRequest(_ id: String, memberId: String, reason: String?) async throws {
        try await api.rejectJoinRequest(id: id, memberId: memberId, DecideMemberRequest(reason: reason))
    }

    func staff(_ id: String, offset: Int, limit: Int) async throws -> ListWithTotal<ForumMember> {
        try await api.staff(id: id, DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListForumStaff")
    }

    func changeMemberRole(_ id: String, memberId: String, role: ForumMemberRole) async throws {
        try await api.changeMemberRole(id: id, memberId: memberId, ChangeMemberRoleRequest(role: role))
    }

    func removeMember(_ id: String, memberId: String) async throws { try await api.removeMember(id: id, memberId: memberId) }
    func leaveForum(_ id: String) async throws { try await api.leaveForum(id: id) }
    func announcements(_ id: String) async throws -> [ForumAnnouncement] { try await api.announcements(id: id).dataOrThrow("ListForumAnnouncements") }

    func createAnnouncement(_ id: String, _ body: CreateAnnouncementRequest) async throws -> String {
        try await api.createAnnouncement(id: id, body).dataOrThrow("CreateAnnouncement").id
    }

    func patchAnnouncement(_ announcementId: String, _ body: PatchAnnouncementRequest) async throws { try await api.patchAnnouncement(announcementId: announcementId, body) }
    func deleteAnnouncement(_ announcementId: String) async throws { try await api.deleteAnnouncement(announcementId: announcementId) }
    func feed(_ body: FeedRequest) async throws -> ListWithNextCursor<PostCard> { try await api.feed(body).dataOrThrow("DiscussionFeed") }

    func forumStream(_ id: String, after: String, limit: Int, topicId: String?) async throws -> ForumStream {
        try await api.forumStream(id: id, ForumStreamRequest(after: after, limit: limit, topicId: topicId)).dataOrThrow("ForumStream")
    }

    func forumEvents(_ id: String, offset: Int, limit: Int) async throws -> ListWithTotal<ForumEvent> {
        try await api.forumEvents(id: id, DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListForumEvents")
    }

    func topics(_ id: String) async throws -> [ForumTopic] { try await api.topics(id: id).dataOrThrow("ListForumTopics") }
    func createTopic(_ id: String, name: String) async throws -> String { try await api.createTopic(id: id, CreateTopicRequest(name: name)).dataOrThrow("CreateTopic").id }
    func patchTopic(_ topicId: String, _ body: PatchTopicRequest) async throws { try await api.patchTopic(topicId: topicId, body) }
    func deleteTopic(_ topicId: String) async throws { try await api.deleteTopic(topicId: topicId) }

    func setPostTopics(forumId: String, postId: String, topicIds: [String]) async throws {
        try await api.setPostTopics(id: forumId, postId: postId, PostTopicsRequest(topicIds: topicIds))
    }

    func pendingPosts(_ id: String, offset: Int, limit: Int) async throws -> ListWithTotal<ForumPost> {
        try await api.pendingPosts(id: id, DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListPendingPosts")
    }

    func approvePost(_ id: String, postId: String) async throws { try await api.approvePost(id: id, postId: postId) }
    func rejectPost(_ id: String, postId: String, reason: String?) async throws { try await api.rejectPost(id: id, postId: postId, ReasonRequest(reason: reason)) }
    func removePost(_ id: String, postId: String, reason: String?) async throws { try await api.removePost(id: id, postId: postId, ReasonRequest(reason: reason)) }

    func setPostPinned(_ id: String, postId: String, pinned: Bool) async throws {
        if pinned { try await api.pinPost(id: id, postId: postId) } else { try await api.unpinPost(id: id, postId: postId) }
    }

    func myPosts(offset: Int, limit: Int) async throws -> ListWithTotal<ForumPost> {
        try await api.myPosts(MyPostsRequest(offset: offset, limit: limit)).dataOrThrow("ListMyPosts")
    }

    func likedPosts(offset: Int, limit: Int) async throws -> ListWithTotal<PostCard> {
        try await api.likedPosts(DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListLikedPosts")
    }

    func bookmarkedPosts(offset: Int, limit: Int) async throws -> ListWithTotal<PostCard> {
        try await api.bookmarkedPosts(DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListBookmarkedPosts")
    }

    func createPost(_ body: CreatePostRequest) async throws -> PostCreated { try await api.createPost(body).dataOrThrow("CreatePost") }
    func post(_ id: String) async throws -> PostDetail { try await api.post(id: id).dataOrThrow("GetPost") }
    func patchPost(_ id: String, _ body: PatchPostRequest) async throws -> PostPatched { try await api.patchPost(id: id, body).dataOrThrow("PatchPost") }
    func deletePost(_ id: String) async throws { try await api.deletePost(id: id) }

    func publishPost(_ id: String, publications: [PublicationInput]) async throws -> PostPatched {
        try await api.publishPost(id: id, PublishPostRequest(publications: publications)).dataOrThrow("PublishPost")
    }

    func setPostLiked(_ id: String, _ liked: Bool) async throws {
        if liked { try await api.likePost(id: id) } else { try await api.unlikePost(id: id) }
    }

    func setPostBookmarked(_ id: String, _ bookmarked: Bool) async throws {
        if bookmarked { try await api.bookmarkPost(id: id) } else { try await api.unbookmarkPost(id: id) }
    }

    func comments(_ postId: String, after: String, limit: Int, opOnly: Bool) async throws -> ListWithNextCursor<PostComment> {
        try await api.comments(id: postId, CommentStreamRequest(after: after, limit: limit, opOnly: opOnly)).dataOrThrow("ListComments")
    }

    /** 一条顶层评论下面的回复，最早的在前。 */
    func threadReplies(_ postId: String, threadCommentId: String, after: String, limit: Int) async throws -> ListWithNextCursor<PostComment> {
        try await api.comments(id: postId, CommentStreamRequest(after: after, limit: limit, threadCommentId: threadCommentId, opOnly: false)).dataOrThrow("ListComments")
    }

    func createComment(_ postId: String, contentHtml: String, replyToCommentId: String?) async throws -> String {
        try await api.createComment(id: postId, CreateCommentRequest(contentHtml: contentHtml, replyToCommentId: replyToCommentId)).dataOrThrow("CreateComment").id
    }

    func deleteComment(_ commentId: String) async throws { try await api.deleteComment(commentId: commentId) }

    func setCommentLiked(_ commentId: String, _ liked: Bool) async throws {
        if liked { try await api.likeComment(commentId: commentId) } else { try await api.unlikeComment(commentId: commentId) }
    }

    func setCommentBookmarked(_ commentId: String, _ bookmarked: Bool) async throws {
        if bookmarked { try await api.bookmarkComment(commentId: commentId) } else { try await api.unbookmarkComment(commentId: commentId) }
    }

    func bookmarkedComments(offset: Int, limit: Int) async throws -> ListWithTotal<CommentBookmark> {
        try await api.bookmarkedComments(DiscussionPageRequest(offset: offset, limit: limit)).dataOrThrow("ListBookmarkedComments")
    }

    func createReport(_ body: CreateReportRequest) async throws -> String { try await api.createReport(body).dataOrThrow("CreateReport").id }

    func reports(_ id: String, offset: Int, limit: Int, status: ForumReportStatus?) async throws -> ListWithTotal<ForumReport> {
        try await api.reports(id: id, ListReportsRequest(offset: offset, limit: limit, status: status)).dataOrThrow("ListForumReports")
    }

    func resolveReport(_ reportId: String, action: ForumReportAction, note: String) async throws {
        try await api.resolveReport(reportId: reportId, CloseReportRequest(note: note, action: action.rawValue))
    }

    func dismissReport(_ reportId: String, note: String) async throws { try await api.dismissReport(reportId: reportId, CloseReportRequest(note: note)) }
}
