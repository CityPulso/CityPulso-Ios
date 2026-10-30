import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 在写 / 改的公告。 */
struct AnnouncementDraft: Identifiable {
    var id: String { announcementId ?? "new" }
    var announcementId: String?
    var title = ""
    var body = AttributedString()
    var pinned = false
}

/** 还没填理由的驳回 / 移除。 */
struct ReasonPrompt: Identifiable {
    let postId: String
    let remove: Bool
    var id: String { postId }
}

extension ForumDetail {
    var isOwner: Bool { myRole == .owner }
}

/** 论坛管理（所有者 / 管理员，Android `ForumManageViewModel`）：资料和规则、加入申请和管理人员、待审帖子、举报、公告、话题。 */
@MainActor
@Observable
final class ForumManageModel {
    static let announcementMax = 2000

    let forumId: String
    private(set) var forum = Loadable<ForumDetail>()
    var tab = ForumManageTab.settings
    var name = ""
    var description = ""
    var activityTypes: [ForumActivityType] = []
    var settings = ForumSettings()
    private(set) var saving = false
    var reportStatus = ForumReportStatus.open { didSet { if reportStatus != oldValue { reports = discussion.pageReports(forumId, status: reportStatus); reportsGeneration += 1 } } }
    private(set) var announcements: [ForumAnnouncement] = []
    private(set) var topics: [ForumTopic] = []
    var topicName = "" { didSet { if topicName.count > forumTopicNameMax { topicName = String(topicName.prefix(forumTopicNameMax)) } } }
    var announcementDraft: AnnouncementDraft?
    var reasonPrompt: ReasonPrompt?
    private(set) var busyId: String?
    let pictures = ForumPictures()

    let requests: PagedList<ForumMember, Int>
    let staff: PagedList<ForumMember, Int>
    let pending: PagedList<ForumPost, Int>
    private(set) var reports: PagedList<ForumReport, Int>
    private(set) var reportsGeneration = 0

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(forumId: String) {
        self.forumId = forumId
        let service = Container.shared.discussionService()
        requests = service.pageJoinRequests(forumId)
        staff = service.pageStaff(forumId)
        pending = service.pagePendingPosts(forumId)
        reports = service.pageReports(forumId, status: .open)
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    /** 名字、简介、活动类型或规则和已存的不一样。 */
    var formDirty: Bool {
        guard let saved = forum.data else { return false }
        return saved.name != name.trimmingCharacters(in: .whitespaces) || saved.description != description.trimmingCharacters(in: .whitespacesAndNewlines)
            || saved.activityTypes != activityTypes || saved.settings != settings
    }

    var avatarChanged: Bool { forum.data.map { pictures.avatar?.imageId != $0.avatarImageId } ?? false }

    var backgroundsChanged: Bool {
        forum.data.map { saved in pictures.backgrounds.map(\.imageId) != saved.images.sorted { $0.sortOrder < $1.sortOrder }.map { Optional($0.imageId) } } ?? false
    }

    var dirty: Bool { formDirty || avatarChanged || backgroundsChanged }
    var canSave: Bool { dirty && pictures.ready && !saving }

    func observe() async {
        await load(resetForm: true)
        for await _ in discussion.bus.signals(where: { _ in true }) { await load(resetForm: false) }
    }

    func load(resetForm: Bool) async {
        do {
            let saved = try await discussion.forum(forumId)
            let keepForm = !resetForm && formDirty
            let keepPictures = !resetForm && forum.data != nil && (avatarChanged || backgroundsChanged)
            forum = Loadable(data: saved, isLoading: false)
            if !keepForm { applySaved(saved) }
            if !keepPictures { pictures.reset(avatarImageId: saved.avatarImageId, images: saved.images) }
            announcements = (try? await discussion.announcements(forumId)) ?? []
            await loadTopics()
        } catch {
            forum = Loadable(data: forum.data, isLoading: false, error: UiError(error))
        }
    }

    private func applySaved(_ saved: ForumDetail) {
        name = saved.name
        description = saved.description
        activityTypes = saved.activityTypes
        settings = saved.settings
    }

    private func loadTopics() async {
        if let list = try? await discussion.topics(forumId) { topics = list }
    }

    func discard() {
        guard let saved = forum.data else { return }
        applySaved(saved)
        pictures.reset(avatarImageId: saved.avatarImageId, images: saved.images)
    }

    /** 资料和头像走 PATCH，背景图整组 PUT，只发改了的部分。 */
    func save() async {
        guard let saved = forum.data, canSave else { return }
        let old = saved.settings
        let body = PatchForumRequest(
            name: changed(name.trimmingCharacters(in: .whitespaces), saved.name),
            description: changed(description.trimmingCharacters(in: .whitespacesAndNewlines), saved.description),
            activityTypes: changed(activityTypes, saved.activityTypes),
            avatarImageId: avatarChanged ? pictures.avatar?.imageId : nil,
            requiresPostReview: changed(settings.requiresPostReview, old.requiresPostReview),
            onlyFollowersCanPost: changed(settings.onlyFollowersCanPost, old.onlyFollowersCanPost),
            allowComments: changed(settings.allowComments, old.allowComments),
            allowReposts: changed(settings.allowReposts, old.allowReposts),
            allowShares: changed(settings.allowShares, old.allowShares),
            allowPostEdit: changed(settings.allowPostEdit, old.allowPostEdit),
            editableTitle: changed(settings.editableTitle, old.editableTitle),
            editableContent: changed(settings.editableContent, old.editableContent),
            editableMedia: changed(settings.editableMedia, old.editableMedia),
            editRequiresReview: changed(settings.editRequiresReview, old.editRequiresReview)
        )
        let patch = formDirty || avatarChanged
        let replace = backgroundsChanged
        saving = true
        defer { saving = false }
        do {
            if patch { try await discussion.patchForum(forumId, body) }
            if replace { try await discussion.replaceBackgrounds(forumId, pictures.backgroundInputs) }
            PulsoMessageCenter.shared.success("discussion_saved")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    private func changed<T: Equatable>(_ value: T, _ saved: T) -> T? { value == saved ? nil : value }

    func archive() async { await act(forumId) { try await self.discussion.archiveForum(self.forumId) } }
    func reopen() async { await act(forumId) { try await self.discussion.reopenForum(self.forumId) } }

    /** 删掉后返回 true，页面退回论坛之前的那页。 */
    func delete() async -> Bool {
        var done = false
        await act(forumId) {
            try await self.discussion.deleteForum(self.forumId)
            PulsoMessageCenter.shared.success("discussion_forum_deleted")
            done = true
        }
        return done
    }

    func approveRequest(_ member: ForumMember, role: ForumMemberRole) async {
        await act(member.id) { try await self.discussion.approveJoinRequest(self.forumId, memberId: member.id, role: role) }
    }

    func rejectRequest(_ member: ForumMember) async {
        await act(member.id) { try await self.discussion.rejectJoinRequest(self.forumId, memberId: member.id, reason: nil) }
    }

    func changeRole(_ member: ForumMember, role: ForumMemberRole) async {
        await act(member.id) { try await self.discussion.changeMemberRole(self.forumId, memberId: member.id, role: role) }
    }

    func removeMember(_ member: ForumMember) async {
        await act(member.id) { try await self.discussion.removeMember(self.forumId, memberId: member.id) }
    }

    func approvePost(_ post: ForumPost) async {
        await act(post.id) { try await self.discussion.approvePost(self.forumId, postId: post.id) }
    }

    /** 驳回 / 移除要先填理由，作者看得到。 */
    func confirmReason(_ reason: String) async {
        guard let prompt = reasonPrompt else { return }
        reasonPrompt = nil
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.isEmpty ? nil : trimmed
        await act(prompt.postId) {
            if prompt.remove {
                try await self.discussion.removePost(self.forumId, postId: prompt.postId, reason: note)
            } else {
                try await self.discussion.rejectPost(self.forumId, postId: prompt.postId, reason: note)
            }
        }
    }

    func togglePin(_ post: ForumPost) async {
        await act(post.id) { try await self.discussion.setPostPinned(self.forumId, postId: post.id, pinned: !post.isPinned) }
    }

    func resolveReport(_ report: ForumReport, action: ForumReportAction) async {
        await act(report.id) { try await self.discussion.resolveReport(report.id, action: action, note: "") }
    }

    func dismissReport(_ report: ForumReport) async {
        await act(report.id) { try await self.discussion.dismissReport(report.id, note: "") }
    }

    func editAnnouncement(_ announcement: ForumAnnouncement?) {
        announcementDraft = announcement.map {
            AnnouncementDraft(announcementId: $0.id, title: $0.title, body: RichTextHTML.attributed($0.contentHtml), pinned: $0.isPinned)
        } ?? AnnouncementDraft()
    }

    func saveAnnouncement(context: Font.Context) async {
        guard let draft = announcementDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        announcementDraft = nil
        let html = RichTextHTML.html(draft.body, context: context)
        await act(draft.id) {
            if let id = draft.announcementId {
                try await self.discussion.patchAnnouncement(id, PatchAnnouncementRequest(title: title, contentHtml: html, isPinned: draft.pinned))
            } else {
                _ = try await self.discussion.createAnnouncement(self.forumId, CreateAnnouncementRequest(title: title, contentHtml: html, isPinned: draft.pinned))
            }
        }
    }

    func deleteAnnouncement(_ announcement: ForumAnnouncement) async {
        await act(announcement.id) { try await self.discussion.deleteAnnouncement(announcement.id) }
    }

    func addTopic() async {
        let name = topicName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await act("topic:new") {
            _ = try await self.discussion.createTopic(self.forumId, name: name)
            self.topicName = ""
            await self.loadTopics()
        }
    }

    func renameTopic(_ topic: ForumTopic, name: String) async {
        await act(topic.id) {
            try await self.discussion.renameTopic(topic.id, name: name)
            await self.loadTopics()
        }
    }

    /** 和相邻的一个交换位置（与 WEB 管理台一样）。 */
    func moveTopic(from: Int, to: Int) async {
        let rows = topics
        guard rows.indices.contains(from), rows.indices.contains(to) else { return }
        await act(rows[from].id) {
            try await self.discussion.moveTopic(rows[from].id, sortOrder: to)
            try await self.discussion.moveTopic(rows[to].id, sortOrder: from)
            await self.loadTopics()
        }
    }

    func deleteTopic(_ topic: ForumTopic) async {
        await act(topic.id) {
            try await self.discussion.deleteTopic(topic.id)
            await self.loadTopics()
        }
    }

    private func act(_ id: String, _ block: () async throws -> Void) async {
        busyId = id
        defer { busyId = nil }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }
}
