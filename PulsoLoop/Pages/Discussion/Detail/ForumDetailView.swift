import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

extension ForumDetail {
    var isStaff: Bool { myRole != nil }
    var canManage: Bool { myRole == .owner || myRole == .admin }
}

/** 活动条上一场关联活动的信息，从它的运动读一次（Android `ForumEventInfo`）。 */
struct ForumEventInfo: Hashable {
    let title: String
    let startsAt: String
    let venueName: String?
    let coverImageId: String?
}

/**
 * 一个论坛（Android `ForumDetailViewModel`）：封面头部（收藏 / 发帖 / 更多），帖子（话题筛选、大家在这里招人的活动、公告、
 * 置顶在前）、简介、管理人员、规则。
 */
@MainActor
@Observable
final class ForumDetailModel {
    let forumId: String
    private(set) var forum = Loadable<ForumDetail>()
    var tab = ForumDetailTab.posts
    private(set) var announcements: [ForumAnnouncement] = []
    private(set) var topics: [ForumTopic] = []
    var topicId: String? { didSet { if topicId != oldValue { reloadPosts() } } }
    private(set) var eventInfo: [String: ForumEventInfo] = [:]
    var joinOpen = false
    var joinMessage = ""
    private(set) var busy = false
    var reporting: ForumPost?
    private(set) var reportBusy = false
    private(set) var posts: PagedList<ForumPost, String>
    let staff: PagedList<ForumMember, Int>
    let events: PagedList<ForumEvent, Int>
    private(set) var postsGeneration = 0

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.loopSportServices) private var sportServices
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(forumId: String) {
        self.forumId = forumId
        let service = Container.shared.discussionService()
        posts = service.pageForumPosts(forumId)
        staff = service.pageStaff(forumId)
        events = service.pageForumEvents(forumId)
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    func observe() async {
        await load()
        for await _ in discussion.bus.signals(where: { _ in true }) { await load() }
    }

    func load() async {
        forum.isLoading = true
        do {
            forum = try await Loadable(data: discussion.forum(forumId), isLoading: false)
        } catch {
            forum = Loadable(data: forum.data, isLoading: false, error: UiError(error))
            return
        }
        announcements = (try? await discussion.announcements(forumId)) ?? []
        topics = (try? await discussion.topics(forumId)) ?? []
        if let topicId, !topics.contains(where: { $0.id == topicId }) { self.topicId = nil }
    }

    private func reloadPosts() {
        posts = discussion.pageForumPosts(forumId, topicId: topicId)
        postsGeneration += 1
    }

    /** 活动条第一次显示某场活动时读它的标题、时间、场地和照片。 */
    func ensureEvent(_ event: ForumEvent) {
        guard eventInfo[event.eventId] == nil, let service = sportServices[event.sport] else { return }
        Task {
            for await response in service.detail(eventId: event.eventId) {
                if case let .data(detail) = response {
                    eventInfo[event.eventId] = ForumEventInfo(title: detail.event.title, startsAt: detail.event.startsAt, venueName: detail.event.venueName, coverImageId: detail.imageIds.first)
                    return
                }
                if case .error = response { return }
            }
        }
    }

    func toggleFollow() async {
        guard let data = forum.data else { return }
        await act { try await self.discussion.setForumFavorite(self.forumId, !data.favoritedByMe) }
    }

    func apply() async {
        let message = joinMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        joinOpen = false
        joinMessage = ""
        await act {
            try await self.discussion.applyToForum(self.forumId, message: message)
            PulsoMessageCenter.shared.success("discussion_join_sent")
        }
    }

    func toggleLike(_ post: ForumPost) async {
        let liked = !post.likedByMe
        posts.update(where: { $0.id == post.id }) { $0.likedByMe = liked; $0.likeCount = max(0, $0.likeCount + (liked ? 1 : -1)) }
        do {
            try await discussion.setPostLiked(post.id, liked)
        } catch {
            posts.update(where: { $0.id == post.id }) { $0.likedByMe = !liked; $0.likeCount = max(0, $0.likeCount + (liked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    func toggleBookmark(_ post: ForumPost) async {
        let bookmarked = !post.bookmarkedByMe
        posts.update(where: { $0.id == post.id }) { $0.bookmarkedByMe = bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? 1 : -1)) }
        do {
            try await discussion.setPostBookmarked(post.id, bookmarked)
        } catch {
            posts.update(where: { $0.id == post.id }) { $0.bookmarkedByMe = !bookmarked; $0.bookmarkCount = max(0, $0.bookmarkCount + (bookmarked ? -1 : 1)) }
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
        }
    }

    func submitReport(_ reason: ForumReportReason, _ detail: String) async {
        guard let post = reporting else { return }
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

    private func act(_ block: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await block() } catch { PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed") }
    }
}

/** 论坛页（Android `ForumDetailScreen`）。 */
struct ForumDetailView: View {
    @State private var model: ForumDetailModel
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(forumId: String) {
        _model = State(initialValue: ForumDetailModel(forumId: forumId))
    }

    var body: some View {
        Group {
            if let forum = model.forum.data {
                content(forum)
            } else if let error = model.forum.error {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text(verbatim: model.forum.data?.name ?? String(localized: "shell_dest_forum")))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .task(id: model.postsGeneration) { await model.posts.observe() }
        .task { await model.staff.observe() }
        .task { await model.events.observe() }
        .sheet(item: $model.reporting) { _ in
            ReportSheet(busy: model.reportBusy) { reason, detail in Task { await model.submitReport(reason, detail) } }
        }
        .sheet(isPresented: $model.joinOpen) { joinSheet }
    }

    private func content(_ forum: ForumDetail) -> some View {
        List {
            header(forum)
            Section {
                Picker(selection: $model.tab) {
                    ForEach(ForumDetailTab.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            switch model.tab {
            case .posts: posts(forum)
            case .about: about(forum)
            case .staff: staff
            case .rules: rules(forum.settings)
            }
        }
        .refreshable { await model.load() }
    }

    private func header(_ forum: ForumDetail) -> some View {
        Section {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(.tint.opacity(0.2))
                if let cover = model.imageURL(forum.coverImageId) { PulsoRemoteImage(url: cover) }
                PulsoRemoteImage(url: model.imageURL(forum.avatarImageId))
                    .frame(width: 56, height: 56)
                    .background(.fill.tertiary)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemBackground), lineWidth: 2))
                    .padding(12)
            }
            .frame(height: 150)
            .clipped()
            .listRowInsets(EdgeInsets())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: forum.name).font(.title3.bold())
                    ForumBadge(scope: forum.owner.profileScope)
                }
                Text(verbatim: localizedFormat("discussion_forum_stats", forum.favoriteCount, forum.postCount, forum.staffCount)).font(.caption).foregroundStyle(.secondary)
                if forum.status == .archived {
                    Text("discussion_forum_archived").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button {
                        Task { await model.toggleFollow() }
                    } label: {
                        Label((forum.favoritedByMe ? "discussion_unfollow" : "discussion_follow") as LocalizedStringKey, systemImage: forum.favoritedByMe ? "star.fill" : "star")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pulso())
                    .disabled(model.busy)
                    if forum.status == .active {
                        NavigationLink(value: LoopRoute.postCreate(prefill: PostCreatePrefill(forumId: forum.id))) {
                            Text("discussion_post_here").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pulso(.soft))
                    }
                    Menu {
                        if forum.canManage {
                            NavigationLink(value: LoopRoute.forumManage(forumId: forum.id)) { Label("discussion_manage", systemImage: "gearshape") }
                        } else if let role = forum.myRole {
                            Label { Text(role.labelKey) } icon: { Image(systemName: "person.text.rectangle") }
                        } else if forum.pendingRequest {
                            Label("discussion_join_pending", systemImage: "hourglass")
                        } else {
                            Button { model.joinOpen = true } label: { Label("discussion_join", systemImage: "person.badge.plus") }
                                .disabled(forum.status != .active)
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 36, height: 30)
                    }
                    .buttonStyle(.pulso(.soft))
                    .accessibilityLabel(Text("discussion_more_actions"))
                }
            }
        }
    }

    @ViewBuilder
    private func posts(_ forum: ForumDetail) -> some View {
        if !model.topics.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    topicChip(Text("discussion_topics_all"), selected: model.topicId == nil) { model.topicId = nil }
                    ForEach(model.topics, id: \.id) { topic in
                        topicChip(Text(verbatim: "#\(topic.name)"), selected: model.topicId == topic.id) { model.topicId = topic.id }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        if !model.events.items.isEmpty {
            Section("discussion_forum_events") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.events.items, id: \.eventId) { event in
                            eventCard(event)
                                .onAppear {
                                    model.ensureEvent(event)
                                    if event.eventId == model.events.items.last?.eventId { model.events.loadMore() }
                                }
                        }
                    }
                }
            }
        }
        if !model.announcements.isEmpty {
            Section("discussion_announcements") {
                ForEach(model.announcements, id: \.id) { announcement in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if announcement.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint) }
                            Text(verbatim: announcement.title).font(.subheadline.weight(.semibold))
                        }
                        RichTextBody(html: announcement.contentHtml, lineLimit: 4)
                    }
                }
            }
        }
        let posts = model.posts
        if posts.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160).listRowBackground(Color.clear)
        } else if let error = posts.error {
            PulsoLoadErrorView(error) { Task { await posts.refresh() } }.listRowBackground(Color.clear)
        } else if posts.isEmpty {
            ContentUnavailableView {
                Text("discussion_forum_empty")
            } description: {
                Text("discussion_forum_empty_body")
            } actions: {
                if forum.status == .active {
                    NavigationLink("discussion_post_here", value: LoopRoute.postCreate(prefill: PostCreatePrefill(forumId: forum.id))).buttonStyle(.pulso())
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
                    onRepost: forum.settings.allowReposts ? { shell?.push(LoopRoute.postCreate(prefill: PostCreatePrefill(repostOfPostId: post.id, forumId: forum.id))) } : nil,
                    onOpenAuthor: { shell?.push(LoopRoute.socialProfile(profileId: post.author.profileId)) },
                    onOpenTopic: { model.topicId = $0.id },
                    pinned: post.isPinned,
                    hideForums: true,
                    onReport: { model.reporting = post }
                )
                .onAppear { if post.id == posts.items.last?.id { posts.loadMore() } }
            }
        }
    }

    private func topicChip(_ label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func eventCard(_ event: ForumEvent) -> some View {
        let info = model.eventInfo[event.eventId]
        return Button { shell?.push(LoopRoute.event(sport: event.sport, eventId: event.eventId)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                SportCover(url: model.imageURL(info?.coverImageId), sport: event.sport, iconSize: 28)
                    .frame(width: 180, height: 90)
                    .clipShape(.rect(cornerRadius: 8))
                Text(verbatim: info?.title ?? event.postTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(verbatim: [info.flatMap { DateTimeFormatters.monthDayTime($0.startsAt) }, info?.venueName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 180, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func about(_ forum: ForumDetail) -> some View {
        Section {
            if !forum.description.isEmpty { Text(verbatim: forum.description) }
            Button { shell?.push(LoopRoute.socialProfile(profileId: forum.owner.profileId)) } label: {
                HStack {
                    Text("discussion_owner_label").foregroundStyle(.secondary)
                    Spacer()
                    AuthorLine(author: forum.owner, at: forum.createdAt, avatarURL: model.imageURL(forum.owner.avatarImageId))
                }
            }
            .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 6) {
                Text("discussion_forum_sport").font(.subheadline.bold())
                ForumTypeTags(types: forum.sports)
            }
            if !model.topics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("discussion_topics_title").font(.subheadline.bold())
                    TopicChipRow(topics: model.topics.map { PostTopic(id: $0.id, forumId: $0.forumId, name: $0.name) })
                }
            }
        }
    }

    @ViewBuilder
    private var staff: some View {
        let staff = model.staff
        if staff.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if staff.items.isEmpty {
            Text("discussion_staff_empty").foregroundStyle(.secondary)
        } else {
            ForEach(staff.items, id: \.id) { member in
                HStack {
                    AuthorLine(author: member.profile, at: member.createdAt, avatarURL: model.imageURL(member.profile.avatarImageId)) {
                        shell?.push(LoopRoute.socialProfile(profileId: member.profile.profileId))
                    }
                    Spacer()
                    Text(member.role.labelKey).font(.caption.weight(.medium)).foregroundStyle(.tint)
                }
                .onAppear { if member.id == staff.items.last?.id { staff.loadMore() } }
            }
        }
    }

    /** 论坛规则，编号列出（Android `RulesCard`）。 */
    private func rules(_ s: ForumSettings) -> some View {
        let rules: [LocalizedStringKey] = [
            s.requiresPostReview ? "discussion_rule_reviewed" : "discussion_rule_open",
            s.onlyFollowersCanPost ? "discussion_rule_followers_only" : "discussion_rule_anyone",
            s.allowComments ? "discussion_rule_comments" : "discussion_rule_no_comments",
            s.allowReposts ? "discussion_rule_reposts" : "discussion_rule_no_reposts",
            !s.allowPostEdit ? "discussion_rule_no_edit" : (s.editRequiresReview ? "discussion_rule_edit_reviewed" : "discussion_rule_edit"),
        ]
        return Section("discussion_rules_title") {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                        .background(.tint.opacity(0.12), in: .circle)
                    Text(rule)
                }
            }
        }
    }

    private var joinSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("discussion_join", text: Binding(get: { model.joinMessage }, set: { model.joinMessage = String($0.prefix(300)) }), prompt: Text("discussion_join_placeholder"), axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("discussion_join_body")
                }
            }
            .navigationTitle(Text(verbatim: localizedFormat("discussion_join_title", model.forum.data?.name ?? "")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("discussion_cancel") { model.joinOpen = false } }
                ToolbarItem(placement: .confirmationAction) { Button("discussion_join_submit") { Task { await model.apply() } } }
            }
        }
        .presentationDetents([.medium])
    }
}

