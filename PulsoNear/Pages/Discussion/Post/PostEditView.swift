import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 帖子所在的每个论坛都允许改的部分；锁住的字段只读（Android `EditRules`）。 */
struct EditRules {
    let allowed: Bool
    let title: Bool
    let content: Bool
    let media: Bool
    let reviewForums: [String]
}

extension PostDetail {
    func editRules() -> EditRules {
        let scope = live.isEmpty ? publications : live
        return EditRules(
            allowed: scope.allSatisfy(\.allowPostEdit),
            title: scope.allSatisfy(\.editableTitle),
            content: scope.allSatisfy(\.editableContent),
            media: scope.allSatisfy(\.editableMedia),
            reviewForums: scope.filter(\.editRequiresReview).map(\.forumName)
        )
    }

    /** 每个论坛里帖子带的话题。 */
    var topicIdsByForum: [String: Set<String>] {
        Dictionary(grouping: topics, by: \.forumId).mapValues { Set($0.map(\.id)) }
    }
}

/** 编辑帖子（Android `PostEditViewModel`）：只发改了的字段，锁住的字段从不发；话题按论坛单独存。 */
@MainActor
@Observable
final class PostEditModel {
    let postId: String
    let draft = PostDraft()
    private(set) var post = Loadable<PostDetail>()
    private(set) var saving = false

    @ObservationIgnored @Injected(\.discussionService) private var discussion

    init(postId: String) {
        self.postId = postId
        draft.sections = []
    }

    func load() async {
        post = Loadable(data: post.data, isLoading: true)
        do {
            let detail = try await discussion.post(postId)
            post = Loadable(data: detail, isLoading: false)
            draft.kind = detail.kind
            draft.city = detail.city ?? ""
            draft.title = detail.title
            draft.setStoredPhotos(detail.images.sorted { $0.sortOrder < $1.sortOrder }.map(\.imageId))
            draft.sections = sectionDrafts(detail.sections, photos: draft.photos)
            draft.topicIds = detail.topicIdsByForum
            await draft.loadTopics(detail.live.map(\.forumId))
        } catch {
            post = Loadable(data: post.data, isLoading: false, error: UiError(error))
        }
    }

    /** 保存；没改什么就直接返回。返回 true 表示可以关页面。 */
    func save(context: Font.Context) async -> Bool {
        guard let post = post.data, !saving, !draft.uploading else { return false }
        let rules = post.editRules()
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rules.title && trimmedTitle != post.title && draft.titleOk ? trimmedTitle : nil
        let stored = post.sections.map(Self.withoutId)
        let written = draft.sections.sections(photos: draft.photos, context: context)
        let sections = (rules.content || rules.media) && written != stored
            && draft.sections.ready(photos: draft.photos, allowEmpty: post.repostOf != nil) && draft.bodyText.count <= postBodyMax ? written : nil
        let currentIds = draft.photos.compactMap(\.imageId)
        let images = rules.media && currentIds != post.images.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.imageId) ? draft.imageInputs : nil
        let kind = draft.kind != post.kind ? draft.kind : nil
        // "" 清掉原来的城市；没改就不放进请求。
        let trimmedCity = draft.city.trimmingCharacters(in: .whitespaces)
        let city = trimmedCity != (post.city ?? "") ? trimmedCity : nil
        let before = post.topicIdsByForum
        let topicChanges = post.live.map(\.forumId).filter { (draft.topicIds[$0] ?? []) != (before[$0] ?? []) }
        let patch = title != nil || sections != nil || images != nil || kind != nil || city != nil
        guard patch || !topicChanges.isEmpty else { return true }
        saving = true
        do {
            for forumId in topicChanges {
                try await discussion.setPostTopics(forumId: forumId, postId: postId, topicIds: Array(draft.topicIds[forumId] ?? []))
            }
            let patched = patch ? try await discussion.patchPost(postId, PatchPostRequest(kind: kind, city: city, title: title, sections: sections, images: images)) : nil
            PulsoMessageCenter.shared.success((patched?.publications ?? []).contains { $0.status == .pending } ? "discussion_post_resubmitted" : "discussion_saved")
            return true
        } catch {
            saving = false
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
            return false
        }
    }

    /** 比较正文有没有改时不看段落 id。 */
    private static func withoutId(_ section: PostSection) -> PostSection {
        switch section {
        case let .textSection(text): .textSection(TextSection(contentHtml: text.contentHtml))
        case let .imageSection(image): .imageSection(ImageSection(imageId: image.imageId))
        case let .linkSection(link): .linkSection(LinkSection(link: link.link))
        }
    }
}

/** 编辑帖子页（Android `PostEditScreen`）：论坛不允许改的字段只读，并说明原因。 */
struct PostEditView: View {
    @State private var model: PostEditModel
    @State private var sheet: PostFormSheet?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontResolutionContext) private var fontContext

    init(postId: String) {
        _model = State(initialValue: PostEditModel(postId: postId))
    }

    var body: some View {
        @Bindable var draft = model.draft
        Group {
            if let post = model.post.data {
                form(post, draft: draft)
            } else if let error = model.post.error {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("discussion_edit_post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let post = model.post.data, post.isAuthor, post.editRules().allowed {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await model.save(context: fontContext) { dismiss() } }
                    } label: {
                        if model.saving { ProgressView() } else { Text("discussion_save") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(model.saving || draft.uploading || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $draft.linkTarget) { _ in
            LinkPickerSheet(imageURL: draft.imageURL) { draft.pickLink($0) }
        }
    }

    @ViewBuilder
    private func form(_ post: PostDetail, draft: PostDraft) -> some View {
        @Bindable var draft = draft
        let rules = post.editRules()
        Form {
            if !post.isAuthor {
                Text("discussion_edit_not_author").foregroundStyle(.red)
            } else if !rules.allowed {
                Text("discussion_edit_not_allowed").foregroundStyle(.red)
            } else {
                Section {
                    if !rules.reviewForums.isEmpty {
                        Text(verbatim: localizedFormat("discussion_edit_review_notice", rules.reviewForums.joined(separator: "、")))
                            .font(.footnote).foregroundStyle(Color.accentColor)
                    }
                    TextField("discussion_post_title_placeholder", text: $draft.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .disabled(!rules.title)
                        .onChange(of: draft.title) { _, value in
                            if value.count > postTitleMax { draft.title = String(value.prefix(postTitleMax)) }
                        }
                } footer: {
                    if rules.title {
                        Text(verbatim: "\(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count) / \(postTitleMax)")
                    } else {
                        Text("discussion_edit_locked")
                    }
                }
                if !rules.content {
                    Text("discussion_edit_locked").font(.footnote).foregroundStyle(.secondary)
                }
                PostBodyFields(
                    draft: draft,
                    locks: SectionLocks(content: !rules.content, media: !rules.media),
                    showPhotos: post.repostOf == nil && (!draft.photos.isEmpty || !rules.media),
                    mediaLockedCount: rules.media ? nil : post.images.count,
                    enabled: !model.saving
                )
                PostDetailsRows(
                    kind: draft.kind,
                    forumsValue: "\(draft.topicCount) · \(post.live.count)",
                    city: draft.city,
                    onKind: { sheet = .kind },
                    onForums: { sheet = .forums },
                    onCity: { sheet = .city }
                )
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .kind: PostKindSheet(kind: $draft.kind)
            case .city: PostCitySheet(city: $draft.city)
            case .forums: forumsSheet(post)
            }
        }
    }

    /** 帖子所在的论坛（发出后不能改），每个勾话题（Android edit `PostForumsSheet`）。 */
    private func forumsSheet(_ post: PostDetail) -> some View {
        NavigationStack {
            List(post.live, id: \.forumId) { publication in
                SelectedForumPanel(
                    name: publication.forumName,
                    ownerScope: publication.ownerProfileScope,
                    avatarURL: nil,
                    reviewed: publication.editRequiresReview,
                    staff: false,
                    topics: model.draft.topics[publication.forumId] ?? [],
                    picked: model.draft.topicIds[publication.forumId] ?? [],
                    onToggleTopic: { model.draft.toggleTopic(forumId: publication.forumId, topicId: $0) }
                )
                .listRowSeparator(.hidden)
            }
            .navigationTitle("discussion_post_forums_row")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
