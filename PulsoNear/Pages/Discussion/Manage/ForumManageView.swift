import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 论坛管理页（Android `ForumManageScreen`）：设置、管理人员、待审、举报、公告、话题六个标签。 */
struct ForumManageView: View {
    @State private var model: ForumManageModel
    @State private var confirm: PulsoHoldConfirm?
    @State private var reason = ""
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(\.locale) private var locale

    init(forumId: String) {
        _model = State(initialValue: ForumManageModel(forumId: forumId))
    }

    var body: some View {
        Group {
            if let forum = model.forum.data {
                if forum.canManage {
                    content(forum)
                } else {
                    PulsoEmptyState(Text("discussion_manage_no_access"))
                }
            } else if let error = model.forum.error {
                PulsoLoadErrorView(error) { Task { await model.load(resetForm: false) } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text(verbatim: localizedFormat("discussion_manage_title", model.forum.data?.name ?? "")))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .pulsoHoldConfirm($confirm)
        .alert(
            Text((model.reasonPrompt?.remove == true ? "discussion_remove_post_title" : "discussion_reject_post_title") as LocalizedStringKey),
            isPresented: Binding(get: { model.reasonPrompt != nil }, set: { if !$0 { model.reasonPrompt = nil } })
        ) {
            TextField("discussion_reject_reason_placeholder", text: $reason)
            Button((model.reasonPrompt?.remove == true ? "discussion_remove_post" : "discussion_pending_reject") as LocalizedStringKey, role: .destructive) {
                let text = String(reason.prefix(300))
                reason = ""
                Task { await model.confirmReason(text) }
            }
            Button("discussion_cancel", role: .cancel) { reason = "" }
        } message: {
            Text("discussion_reject_post_body")
        }
        .sheet(item: $model.announcementDraft) { _ in announcementSheet }
    }

    private func content(_ forum: ForumDetail) -> some View {
        List {
            Section {
                PulsoUnderlineTabRow(ForumManageTab.allCases, selection: $model.tab) { Text($0.labelKey) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            switch model.tab {
            case .settings: settings(forum)
            case .staff: staffTab(forum)
            case .pending: pendingTab
            case .reports: reportsTab
            case .announcements: announcementsTab
            case .topics: topicsTab
            }
        }
        .task(id: model.tab) {
            switch model.tab {
            case .staff:
                await concurrently([{ await model.requests.observe() }, { await model.staff.observe() }])
            case .pending:
                await model.pending.observe()
            default:
                break
            }
        }
        .task(id: model.reportsGeneration) { if model.tab == .reports { await model.reports.observe() } }
        .onChange(of: model.tab) { _, tab in
            if tab == .reports { Task { await model.reports.refresh() } }
        }
    }

    /* ------------------------------ 设置 ------------------------------ */

    @ViewBuilder
    private func settings(_ forum: ForumDetail) -> some View {
        Section("discussion_forum_name") {
            TextField("discussion_forum_name_placeholder", text: Binding(get: { model.name }, set: { if $0.count <= forumNameMax { model.name = $0 } }))
        }
        Section("discussion_forum_description") {
            TextField("discussion_forum_description_placeholder", text: Binding(get: { model.description }, set: { if $0.count <= forumDescriptionMax { model.description = $0 } }), axis: .vertical)
                .lineLimit(3 ... 8)
        }
        Section("discussion_forum_activity_type") {
            ForumTypePicker(selected: $model.activityTypes, keepOne: true)
                .disabled(model.saving)
        }
        ForumPicturesEditor(pictures: model.pictures, imageURL: model.imageURL, enabled: !model.saving)
        Section("discussion_rules_title") {
            ForumSettingsEditor(settings: $model.settings)
        }
        Section {
            HStack {
                Button {
                    Task { await model.save() }
                } label: {
                    if model.saving { ProgressView() } else { Text("discussion_save").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.pulso())
                .disabled(!model.canSave)
                Button { model.discard() } label: { Text("discussion_discard").frame(maxWidth: .infinity) }
                    .buttonStyle(.pulso(.soft))
                    .disabled(!model.dirty)
            }
            .listRowBackground(Color.clear)
        }
        if forum.isOwner {
            Section {
                if forum.status == .active {
                    Button("discussion_archive") {
                        confirm = PulsoHoldConfirm(
                            title: localizedFormat("discussion_archive_title", forum.name),
                            message: String(localized: "discussion_archive_body"),
                            label: String(localized: "discussion_archive")
                        ) { Task { await model.archive() } }
                    }
                } else {
                    Button("discussion_reopen") { Task { await model.reopen() } }
                }
                Button("discussion_delete", role: .destructive) {
                    confirm = PulsoHoldConfirm(
                        title: localizedFormat("discussion_delete_title", forum.name),
                        message: String(localized: "discussion_delete_body"),
                        label: String(localized: "discussion_delete")
                    ) {
                        Task {
                            // 论坛没了：管理页和论坛页都退出去。
                            guard await model.delete() else { return }
                            if let shell { shell.pop(2) } else { dismiss() }
                        }
                    }
                }
            } header: {
                Text("discussion_lifecycle")
            } footer: {
                Text((forum.status == .active ? "discussion_archive_hint" : "discussion_archived_hint") as LocalizedStringKey)
            }
        }
    }

    /* ------------------------------ 管理人员 ------------------------------ */

    @ViewBuilder
    private func staffTab(_ forum: ForumDetail) -> some View {
        Section("discussion_manage_requests") {
            pagedRows(model.requests, empty: "discussion_manage_no_requests") { member in
                requestRow(member)
            }
        }
        Section("discussion_manage_tab_staff") {
            pagedRows(model.staff, empty: "discussion_staff_empty") { member in
                staffRow(member, owner: forum.isOwner)
            }
        }
    }

    private func requestRow(_ member: ForumMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AuthorLine(author: member.profile, at: member.createdAt, avatarURL: model.imageURL(member.profile.avatarImageId)) {
                shell?.push(NearRoute.socialProfile(profileId: member.profile.profileId))
            }
            if let message = member.message, !message.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: message).font(.subheadline)
            }
            HStack {
                ForEach(ForumMemberRole.grantable, id: \.self) { role in
                    Button(localizedFormat("discussion_manage_approve_as", String(localized: role.labelResource))) {
                        Task { await model.approveRequest(member, role: role) }
                    }
                    .buttonStyle(.pulso(.soft))
                    .tint(role == .moderator ? .accentColor : .primary)
                }
                Button("discussion_manage_reject") { Task { await model.rejectRequest(member) } }.buttonStyle(.pulso(.soft, tone: .gray))
                if model.busyId == member.id { ProgressView() }
            }
            .controlSize(.small)
            .disabled(model.busyId == member.id)
        }
    }

    private func staffRow(_ member: ForumMember, owner: Bool) -> some View {
        HStack {
            AuthorLine(author: member.profile, at: "", avatarURL: model.imageURL(member.profile.avatarImageId))
            Spacer()
            if member.role == .owner || !owner {
                Text(member.role.labelKey).font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
            } else {
                Menu {
                    Picker("discussion_manage_tab_staff", selection: Binding(get: { member.role }, set: { role in Task { await model.changeRole(member, role: role) } })) {
                        ForEach(ForumMemberRole.grantable, id: \.self) { Text($0.labelKey).tag($0) }
                    }
                    Button("discussion_manage_remove", role: .destructive) {
                        confirm = PulsoHoldConfirm(
                            title: String(localized: "discussion_manage_remove_title"),
                            message: localizedFormat("discussion_manage_remove_body", member.profile.displayName ?? ""),
                            label: String(localized: "discussion_manage_remove")
                        ) { Task { await model.removeMember(member) } }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(member.role.labelKey)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                }
                .disabled(model.busyId == member.id)
            }
        }
    }

    /* ------------------------------ 待审 / 举报 ------------------------------ */

    @ViewBuilder
    private var pendingTab: some View {
        let list = model.pending
        if list.isEmpty {
            PulsoEmptyState(Text("discussion_pending_empty"), description: Text("discussion_pending_empty_body"))
            .listRowBackground(Color.clear)
        } else {
            pagedRows(list, empty: "discussion_pending_empty") { post in
                VStack(alignment: .leading, spacing: 8) {
                    PostCardView(
                        post: post,
                        imageURL: model.imageURL,
                        onOpen: { shell?.push(NearRoute.post(postId: post.id)) },
                        onLike: {},
                        onBookmark: {},
                        status: post.status,
                        hideForums: true
                    )
                    HStack {
                        Button("discussion_pending_approve") { Task { await model.approvePost(post) } }.buttonStyle(.pulso())
                        Button("discussion_pending_reject") { model.reasonPrompt = ReasonPrompt(postId: post.id, remove: false) }.buttonStyle(.pulso(.soft, tone: .gray))
                        if model.busyId == post.id { ProgressView() }
                    }
                    .controlSize(.small)
                    .disabled(model.busyId == post.id)
                }
            }
        }
    }

    @ViewBuilder
    private var reportsTab: some View {
        Section {
            PulsoHighlightTabRow(ForumReportStatus.allCases, selection: $model.reportStatus) { Text($0.labelKey) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            pagedRows(model.reports, empty: "discussion_reports_empty") { report in
                reportRow(report)
            }
        }
    }

    private func reportRow(_ report: ForumReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: [
                String(localized: (report.targetType == .post ? "discussion_report_target_post" : "discussion_report_target_comment") as String.LocalizationValue),
                String(localized: report.reason.labelResource),
                String(localized: report.status.labelResource),
                DateTimeFormatters.monthDayTime(report.createdAt, locale: locale) ?? "",
            ].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
            Button {
                if let postId = report.targetPostId { shell?.push(NearRoute.post(postId: postId)) }
            } label: {
                Text(verbatim: report.targetExcerpt).font(.subheadline).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if let detail = report.detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
            }
            Text(verbatim: localizedFormat("discussion_reported_by", report.reporter.displayName ?? "")).font(.caption2).foregroundStyle(.secondary)
            if report.status == .open {
                HStack {
                    ForEach(report.targetType == .comment ? [ForumReportAction.deleteComment, .none] : [.removePost, .none], id: \.self) { action in
                        Button(action.labelKey) { Task { await model.resolveReport(report, action: action) } }
                            .buttonStyle(.pulso(.soft))
                            .tint(action == .none ? .primary : .accentColor)
                    }
                    Button("discussion_report_dismiss") { Task { await model.dismissReport(report) } }.buttonStyle(.pulso(.soft, tone: .gray))
                    if model.busyId == report.id { ProgressView() }
                }
                .controlSize(.small)
                .disabled(model.busyId == report.id)
            }
        }
    }

    /* ------------------------------ 公告 ------------------------------ */

    @ViewBuilder
    private var announcementsTab: some View {
        Section {
            Button { model.editAnnouncement(nil) } label: { Label("discussion_announcement_new", systemImage: "plus") }
            if model.announcements.isEmpty {
                Text("discussion_announcements_empty").font(.footnote).foregroundStyle(.secondary)
            }
        }
        ForEach(model.announcements, id: \.id) { announcement in
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        if announcement.isPinned {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.accentColor)
                                .accessibilityLabel(Text("discussion_pinned"))
                        }
                        Text(verbatim: announcement.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(verbatim: DateTimeFormatters.monthDayTime(announcement.publishedAt, locale: locale) ?? "").font(.caption2).foregroundStyle(.secondary)
                    }
                    RichTextBody(html: announcement.contentHtml, lineLimit: 3)
                    HStack {
                        Button("discussion_action_edit") { model.editAnnouncement(announcement) }.buttonStyle(.pulso(.soft))
                        Button("discussion_action_delete") {
                            confirm = PulsoHoldConfirm(
                                title: String(localized: "discussion_announcement_delete_title"),
                                message: localizedFormat("discussion_announcement_delete_body", announcement.title),
                                label: String(localized: "discussion_action_delete")
                            ) { Task { await model.deleteAnnouncement(announcement) } }
                        }
                        .buttonStyle(.pulso(.soft))
                        .tint(.secondary)
                    }
                    .controlSize(.small)
                    .disabled(model.busyId == announcement.id)
                }
            }
        }
    }

    private var announcementSheet: some View {
        NavigationStack {
            Form {
                if let draft = model.announcementDraft {
                    Section {
                        TextField("discussion_announcement_title_placeholder", text: Binding(
                            get: { draft.title },
                            set: { if $0.count <= 100 { model.announcementDraft?.title = $0 } }
                        ))
                        RichTextEditor(
                            text: Binding(get: { model.announcementDraft?.body ?? AttributedString() }, set: { model.announcementDraft?.body = $0 }),
                            placeholder: "discussion_announcement_body_placeholder",
                            maxChars: ForumManageModel.announcementMax,
                            minHeight: 120
                        )
                        Toggle("discussion_announcement_pin", isOn: Binding(get: { draft.pinned }, set: { model.announcementDraft?.pinned = $0 }))
                    } footer: {
                        Text("discussion_announcement_hint")
                    }
                }
            }
            .navigationTitle((model.announcementDraft?.announcementId == nil ? "discussion_announcement_new" : "discussion_announcement_edit") as LocalizedStringKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("discussion_cancel") { model.announcementDraft = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let draft = model.announcementDraft
                    Button("discussion_save") { Task { await model.saveAnnouncement(context: fontContext) } }
                        .disabled(draft.map { $0.title.trimmingCharacters(in: .whitespaces).isEmpty || $0.body.characters.count > ForumManageModel.announcementMax } ?? true)
                }
            }
        }
    }

    /* ------------------------------ 话题 ------------------------------ */

    @ViewBuilder
    private var topicsTab: some View {
        let full = model.topics.count >= forumTopicsMax
        Section {
            TextField("discussion_topics_name_placeholder", text: $model.topicName)
                .disabled(full)
            Button {
                Task { await model.addTopic() }
            } label: {
                if model.busyId == "topic:new" { ProgressView() } else { Text("discussion_topics_add") }
            }
            .disabled(full || model.topicName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text("discussion_topics_subtitle").textCase(nil)
                Text(verbatim: localizedFormat("discussion_topics_count", model.topics.count, forumTopicsMax))
            }
        } footer: {
            Text(verbatim: full ? localizedFormat("discussion_topics_full", forumTopicsMax) : localizedFormat("discussion_topics_hint", forumTopicsMax))
        }
        Section {
            if model.topics.isEmpty {
                PulsoEmptyState(Text("discussion_topics_empty"), description: Text("discussion_topics_empty_body"))
            }
            ForEach(Array(model.topics.enumerated()), id: \.element.id) { index, topic in
                TopicRow(
                    topic: topic,
                    first: index == 0,
                    last: index == model.topics.count - 1,
                    busy: model.busyId == topic.id,
                    onRename: { name in Task { await model.renameTopic(topic, name: name) } },
                    onUp: { Task { await model.moveTopic(from: index, to: index - 1) } },
                    onDown: { Task { await model.moveTopic(from: index, to: index + 1) } },
                    onDelete: {
                        confirm = PulsoHoldConfirm(
                            title: localizedFormat("discussion_topics_delete_title", topic.name),
                            message: String(localized: "discussion_topics_delete_body"),
                            label: String(localized: "discussion_topics_delete")
                        ) { Task { await model.deleteTopic(topic) } }
                    }
                )
            }
        }
    }

    /* ------------------------------ 公用 ------------------------------ */

    @ViewBuilder
    private func pagedRows<Item: Identifiable & Sendable, Row: View>(
        _ list: PagedList<Item, Int>, empty: LocalizedStringKey, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            Text(empty).font(.footnote).foregroundStyle(.secondary)
        } else {
            ForEach(list.items) { item in
                row(item).onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }
}

/** 一个话题：上移 / 下移 / 改名 / 删除（删除要按住确认）。 */
private struct TopicRow: View {
    let topic: ForumTopic
    let first: Bool
    let last: Bool
    let busy: Bool
    let onRename: (String) -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onDelete: () -> Void
    @State private var editing = false
    @State private var name = ""

    var body: some View {
        if editing {
            VStack(alignment: .leading, spacing: 8) {
                TextField("discussion_topics_name_label", text: Binding(get: { name }, set: { name = String($0.prefix(forumTopicNameMax)) }))
                HStack {
                    Button("discussion_topics_save") {
                        onRename(name.trimmingCharacters(in: .whitespaces))
                        editing = false
                    }
                    .buttonStyle(.pulso())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces) == topic.name)
                    Button("discussion_cancel") { editing = false }.buttonStyle(.pulso(.soft))
                }
                .controlSize(.small)
            }
        } else {
            HStack {
                Text(verbatim: "#\(topic.name)").fontWeight(.semibold)
                Spacer()
                Group {
                    Button(action: onUp) { Image(systemName: "chevron.up") }.disabled(first)
                        .accessibilityLabel(Text("discussion_topics_move_up"))
                    Button(action: onDown) { Image(systemName: "chevron.down") }.disabled(last)
                        .accessibilityLabel(Text("discussion_topics_move_down"))
                    Button {
                        name = topic.name
                        editing = true
                    } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(Text("discussion_topics_rename"))
                    Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }
                        .accessibilityLabel(Text("discussion_topics_delete"))
                }
                .buttonStyle(.borderless)
                .disabled(busy)
            }
        }
    }
}

extension ForumMember: Identifiable {}
extension ForumReport: Identifiable {}
