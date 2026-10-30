import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 写帖（或转发）发到最多十个论坛（Android `PostCreateViewModel`）；从活动进来时带上活动的标题、描述和照片，
 * 城市按手机位置预填。
 */
@MainActor
@Observable
final class PostCreateModel {
    private static let locationWait: Duration = .seconds(3)

    let draft = PostDraft()
    private(set) var forums: [ForumItem] = []
    private(set) var forumIds: Set<String> = []
    private(set) var activityTitle: String?
    private(set) var repostOf: RepostOf?
    private(set) var submitting = false
    var pickerOpen = false

    @ObservationIgnored private let prefill: PostCreatePrefill
    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.nearActivityServices) private var activityTypeServices
    @ObservationIgnored @Injected(\.locationService) private var location
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.profileStore) private var profileStore

    init(prefill: PostCreatePrefill) {
        self.prefill = prefill
        draft.kind = prefill.kind ?? .discussion
        if let forumId = prefill.forumId { forumIds = [forumId] }
    }

    var authorName: String { profileStore.current.value?.displayName ?? "" }
    var authorAvatarURL: URL? { draft.imageURL(profileStore.current.value?.avatarImageId) }

    var publications: [PublicationInput] {
        forumIds.map { PublicationInput(forumId: $0, topicIds: Array(draft.topicIds[$0] ?? [])) }
    }

    var canSubmit: Bool {
        draft.titleOk && !forumIds.isEmpty && !draft.uploading && !submitting
            && draft.sections.ready(photos: draft.photos, allowEmpty: repostOf != nil) && draft.bodyText.count <= postBodyMax
    }

    func load() async {
        await concurrently([
            { await self.prefillCity() },
            { await self.prefillContent() },
        ])
    }

    private func prefillContent() async {
        if let forumId = prefill.forumId {
            if let list = try? await discussion.forumsByIds([forumId]) { forums = list }
            await draft.loadTopics([forumId])
        }
        if let id = prefill.repostOfPostId, let post = try? await discussion.post(id) {
            repostOf = RepostOf(postId: post.id, title: post.title, contentText: post.contentText, author: post.author, available: true)
        }
        if let activityType = prefill.activityActivityType, let activityId = prefill.activityId, let service = activityTypeServices[activityType] {
            await prefillActivity(service, activityType: activityType, activityId: activityId)
        }
    }

    private func prefillActivity(_ service: any NearActivityService, activityType: NearActivityKind, activityId: String) async {
        for await response in service.detail(activityId: activityId) {
            switch response {
            case .loading: continue
            case .error: return
            case let .data(detail):
                let description = detail.activity.description
                draft.title = detail.activity.title
                // 描述在前，活动作为读者能点开的卡片；活动照片放在下面一排。
                draft.sections = [
                    .newText(RichTextHTML.attributed(paragraphsHTML(description))),
                    .newLink(PostLink(type: .activity, id: activityId, activityType: activityType.activityType)),
                ]
                draft.setStoredPhotos(detail.imageIds)
                activityTitle = detail.activity.title
                return
            }
        }
    }

    /** 最近一次的设备位置所在的城市；作者已经填了就不覆盖。 */
    private func prefillCity() async {
        // 冷启动时位置可能还没回来：最多等 3 秒。
        let deadline = ContinuousClock.now + Self.locationWait
        var point = deviceLocation.location.value?.point
        while point == nil, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            point = deviceLocation.location.value?.point
        }
        guard let point, let city = try? await location.reverseGeocode(lat: point.latitude, lng: point.longitude).cityLabel else { return }
        if draft.city.isEmpty { draft.city = city }
    }

    func pickForums(_ ids: Set<String>) {
        let picked = Set(ids.prefix(postForumsMax))
        pickerOpen = false
        forumIds = picked
        draft.topicIds = draft.topicIds.filter { picked.contains($0.key) }
        Task {
            forums = (try? await discussion.forumsByIds(Array(picked))) ?? []
            await draft.loadTopics(Array(picked))
        }
    }

    func removeForum(_ id: String) {
        forumIds.remove(id)
        forums.removeAll { $0.id == id }
        draft.topicIds[id] = nil
    }

    /** 发出去：全部直接发布时提示「已发布」，否则「已提交审核」；然后把表单换成帖子详情。 */
    func submit(context: Font.Context) async -> String? {
        guard canSubmit else {
            if !draft.sections.ready(photos: draft.photos, allowEmpty: repostOf != nil) {
                PulsoMessageCenter.shared.error(text: String(localized: "discussion_body_required"))
            } else if draft.bodyText.count > postBodyMax {
                PulsoMessageCenter.shared.error(text: localizedFormat("discussion_body_too_long", postBodyMax))
            }
            return nil
        }
        submitting = true
        do {
            let created = try await discussion.createPost(CreatePostRequest(
                kind: draft.kind,
                city: draft.city.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draft.city.trimmingCharacters(in: .whitespaces),
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                sections: draft.sections.sections(photos: draft.photos, context: context),
                images: repostOf == nil ? draft.imageInputs : [],
                publications: publications,
                repostOfPostId: repostOf?.postId
            ))
            PulsoMessageCenter.shared.success(created.publications.allSatisfy { $0.status == .published } ? "discussion_post_published" : "discussion_post_submitted")
            return created.id
        } catch {
            submitting = false
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
            return nil
        }
    }
}

/** 发帖页（Android `PostCreateScreen`）：谁发、发到哪，标题、正文，加正文的四个按钮，照片，最后是类型 / 论坛 / 城市。 */
struct PostCreateView: View {
    @State private var model: PostCreateModel
    @State private var sheet: PostFormSheet?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.fontResolutionContext) private var fontContext

    init(prefill: PostCreatePrefill) {
        _model = State(initialValue: PostCreateModel(prefill: prefill))
    }

    var body: some View {
        @Bindable var draft = model.draft
        Form {
            Section {
                authorRow
                if let repost = model.repostOf { RepostQuote(repost: repost) }
                TextField("discussion_post_title_placeholder", text: $draft.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .onChange(of: draft.title) { _, value in
                        if value.count > postTitleMax { draft.title = String(value.prefix(postTitleMax)) }
                    }
            } footer: {
                Text(verbatim: "\(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count) / \(postTitleMax)")
            }
            PostBodyFields(draft: draft, showPhotos: model.repostOf == nil && !draft.photos.isEmpty, enabled: !model.submitting)
            PostDetailsRows(
                kind: draft.kind,
                forumsValue: "\(draft.topicCount) · \(model.forumIds.count) / \(postForumsMax)",
                city: draft.city,
                activityTitle: model.activityTitle,
                onKind: { sheet = .kind },
                onForums: { sheet = .forums },
                onCity: { sheet = .city }
            )
        }
        .navigationTitle(model.repostOf == nil ? "discussion_new_post" : "discussion_repost_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        if let postId = await model.submit(context: fontContext) { shell?.replaceTop(with: NearRoute.post(postId: postId)) }
                    }
                } label: {
                    if model.submitting { ProgressView() } else { Text("discussion_publish") }
                }
                .buttonStyle(.glassProminent)
                .disabled(!model.canSubmit)
            }
        }
        .task { await model.load() }
        .sheet(item: $sheet) { which in
            switch which {
            case .kind: PostKindSheet(kind: $draft.kind)
            case .city: PostCitySheet(city: $draft.city)
            case .forums: forumsSheet
            }
        }
        .sheet(item: $draft.linkTarget) { _ in
            LinkPickerSheet(imageURL: draft.imageURL) { draft.pickLink($0) }
        }
        .sheet(isPresented: $model.pickerOpen) {
            ForumPickerSheet(selected: model.forumIds, max: postForumsMax) { model.pickForums($0) }
        }
    }

    /** 最上面一行：左边是谁在发，右边「发到」和选好的论坛。 */
    private var authorRow: some View {
        HStack(spacing: 8) {
            PulsoAvatar(url: model.authorAvatarURL, size: 32, fallbackText: model.authorName)
            Text(verbatim: model.authorName).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text("discussion_post_to").font(.caption).foregroundStyle(.secondary)
            Button {
                if model.forums.isEmpty { model.pickerOpen = true } else { sheet = .forums }
            } label: {
                HStack(spacing: 2) {
                    Text(verbatim: forumTarget).lineLimit(1).frame(maxWidth: 140)
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(model.forums.isEmpty ? .secondary : .accentColor)
        }
    }

    private var forumTarget: String {
        switch model.forums.count {
        case 0: String(localized: "discussion_choose_forums")
        case 1: model.forums[0].name
        default: localizedFormat("discussion_forums_picked", model.forums.count)
        }
    }

    /** 选好的论坛，每个勾话题、可以去掉；「选择论坛」打开论坛选择器（Android `PostForumsSheet`）。 */
    private var forumsSheet: some View {
        NavigationStack {
            List {
                Section {
                    if model.forums.isEmpty {
                        Text("discussion_post_forums_none").foregroundStyle(.secondary)
                    }
                    ForEach(model.forums, id: \.id) { forum in
                        SelectedForumPanel(
                            name: forum.name,
                            ownerScope: forum.owner.profileScope,
                            avatarURL: model.draft.imageURL(forum.avatarImageId),
                            reviewed: forum.requiresPostReview,
                            staff: forum.myRole != nil,
                            topics: model.draft.topics[forum.id] ?? [],
                            picked: model.draft.topicIds[forum.id] ?? [],
                            onToggleTopic: { model.draft.toggleTopic(forumId: forum.id, topicId: $0) },
                            onRemove: { model.removeForum(forum.id) }
                        )
                        .listRowSeparator(.hidden)
                    }
                } footer: {
                    Text(verbatim: localizedFormat("discussion_post_forums_hint", postForumsMax))
                }
                Button("discussion_choose_forums") {
                    sheet = nil
                    model.pickerOpen = true
                }
            }
            .navigationTitle("discussion_post_forums")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/** 发帖 / 编辑页的面板。 */
enum PostFormSheet: String, Identifiable {
    case kind, city, forums
    var id: String { rawValue }
}
