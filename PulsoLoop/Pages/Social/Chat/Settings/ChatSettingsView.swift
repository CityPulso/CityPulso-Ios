import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 一个会话里我自己的设置（Android `ConversationSettingsController` + 两种设置页的 VM）：免打扰、置顶、备注、全部已读、壁纸；
 * 群聊另有群名、成员、退出。开关先改再请求，失败退回去并提示。
 */
@MainActor
@Observable
final class ChatSettingsModel {
    let conversationId: String
    let isGroup: Bool
    private(set) var page = Loadable<Bool>()
    private(set) var isMuted = false
    private(set) var isPinned = false
    var customTitle = ""
    private(set) var savedCustomTitle = ""
    private(set) var latestMessageId: String?
    private(set) var isSavingTitle = false
    private(set) var isMarkingRead = false
    var groupTitle = ""
    private(set) var savedGroupTitle = ""
    private(set) var isSavingGroupTitle = false
    /** 群头像；只有群主能改群名和群头像。 */
    private(set) var groupAvatarImageId: String?
    private(set) var isOwner = false
    /** 群头像：按群头像上传（不是自己的头像），确认后设到群上。 */
    @ObservationIgnored private(set) var photoUpload = AvatarUploadModel()
    private(set) var isLeaving = false
    private(set) var wallpaperPath: String?

    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.chatWallpaperStore) private var wallpapers
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(conversationId: String, isGroup: Bool) {
        self.conversationId = conversationId
        self.isGroup = isGroup
        photoUpload = AvatarUploadModel(category: .groupAvatar) { [weak self] imageId in
            guard let self else { return }
            let detail = try await communicationService.updateGroupConversation(conversationId, UpdateGroupRequest(avatarImageId: imageId))
            groupAvatarImageId = detail.avatarImageId
            PulsoMessageCenter.shared.success("chat_settings_group_photo_updated")
        }
    }

    var groupAvatarURL: URL? { ImageURLs.image(groupAvatarImageId, base: config.apiBaseURL) }

    private var type: ConversationType { isGroup ? .group : .direct }

    func observeWallpaper() async {
        for await paths in wallpapers.paths.values() { wallpaperPath = paths[conversationId] }
    }

    func load() async {
        page.isLoading = true
        page.error = nil
        do {
            let setting = try await communicationService.getConversationSetting(type, conversationId)
            let session = sessionStore.state.value
            // 最新一条只用来决定能不能「全部已读」；拿不到就不显示那个操作。
            latestMessageId = try? await communicationService.getMessages(ConversationMessagesKey(
                accountId: session.currentAccountId, profileId: session.currentProfileId, conversationType: type, conversationId: conversationId, limit: 1
            )).items.first?.messageId
            isMuted = setting.isMuted
            isPinned = setting.pinnedAt != nil
            customTitle = setting.customTitle ?? ""
            savedCustomTitle = customTitle
            if isGroup {
                let detail = try await communicationService.getGroupDetail(GroupConversationKey(accountId: session.currentAccountId, profileId: session.currentProfileId, conversationId: conversationId))
                groupTitle = detail.title
                savedGroupTitle = detail.title
                groupAvatarImageId = detail.avatarImageId
                isOwner = detail.createdByProfileId == session.currentProfileId
            }
            page = Loadable(data: true, isLoading: false)
        } catch {
            page = Loadable(data: page.data, isLoading: false, error: UiError(error))
        }
    }

    func setMuted(_ muted: Bool) async {
        guard muted != isMuted else { return }
        isMuted = muted
        do {
            try await communicationService.updateConversationMute(type, conversationId, muted: muted)
        } catch {
            isMuted = !muted
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_save_failed")
        }
    }

    func setPinned(_ pinned: Bool) async {
        guard pinned != isPinned else { return }
        isPinned = pinned
        do {
            try await communicationService.updateConversationPin(type, conversationId, pinned: pinned)
        } catch {
            isPinned = !pinned
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_save_failed")
        }
    }

    var customTitleChanged: Bool {
        customTitle.trimmingCharacters(in: .whitespaces) != savedCustomTitle.trimmingCharacters(in: .whitespaces)
    }

    func saveCustomTitle() async {
        guard customTitleChanged, !isSavingTitle else { return }
        let next = customTitle.trimmingCharacters(in: .whitespaces)
        isSavingTitle = true
        defer { isSavingTitle = false }
        do {
            try await communicationService.updateConversationCustomTitle(type, conversationId, title: next.isEmpty ? nil : next)
            customTitle = next
            savedCustomTitle = next
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_save_failed")
        }
    }

    func markRead() async {
        guard let messageId = latestMessageId, !isMarkingRead else { return }
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            try await communicationService.markConversationRead(type, conversationId, MarkReadRequest(messageId: messageId))
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_mark_read_failed")
        }
    }

    func setWallpaper(_ data: Data) {
        do {
            try wallpapers.set(conversationId, imageData: data)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_wallpaper_failed")
        }
    }

    func clearWallpaper() {
        wallpapers.clear(conversationId)
    }

    var groupTitleChanged: Bool {
        let next = groupTitle.trimmingCharacters(in: .whitespaces)
        return !next.isEmpty && next != savedGroupTitle.trimmingCharacters(in: .whitespaces)
    }

    func saveGroupTitle() async {
        guard groupTitleChanged, !isSavingGroupTitle else { return }
        isSavingGroupTitle = true
        defer { isSavingGroupTitle = false }
        do {
            let detail = try await communicationService.updateGroupConversation(conversationId, UpdateGroupRequest(title: groupTitle.trimmingCharacters(in: .whitespaces)))
            groupTitle = detail.title
            savedGroupTitle = detail.title
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_save_failed")
        }
    }

    func leaveGroup() async -> Bool {
        guard !isLeaving else { return false }
        isLeaving = true
        do {
            try await communicationService.leaveGroupConversation(conversationId)
            return true
        } catch {
            isLeaving = false
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_leave_failed")
            return false
        }
    }
}

/** 聊天设置（Android `DirectChatSettingsScreen` / `GroupChatSettingsScreen` + `ChatSettingsSection`）。 */
struct ChatSettingsView: View {
    @State private var model: ChatSettingsModel
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var confirmingLeave = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(conversationId: String, isGroup: Bool) {
        _model = State(initialValue: ChatSettingsModel(conversationId: conversationId, isGroup: isGroup))
    }

    var body: some View {
        Group {
            if model.page.data != nil {
                form
            } else if let error = model.page.error {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("chat_settings_title")
        .task { await model.load() }
        .task { await model.observeWallpaper() }
        .avatarUploadSheet(model.photoUpload, title: "chat_settings_group_photo_title")
        .onChange(of: wallpaperItem) { _, item in
            guard let item else { return }
            wallpaperItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.setWallpaper(data)
                } else {
                    PulsoMessageCenter.shared.error("chat_settings_wallpaper_failed")
                }
            }
        }
        .sheet(isPresented: $confirmingLeave) {
            // 按住确认（Android `holdConfirm`）。
            VStack(alignment: .leading, spacing: 16) {
                Text("chat_settings_leave_confirm_title").font(.title3.bold())
                Text("chat_settings_leave_hint").foregroundStyle(.secondary)
                PulsoHoldButton("chat_settings_leave", loading: model.isLeaving) {
                    Task {
                        if await model.leaveGroup() {
                            confirmingLeave = false
                            shell?.open(.chatHub)
                        }
                    }
                }
            }
            .padding(24)
            .presentationDetents([.height(240)])
        }
    }

    /** 顶部的群头像和群名；群主点头像角上的相机换头像。 */
    private var groupHeader: some View {
        VStack(spacing: 8) {
            PulsoAvatar(url: model.groupAvatarURL, size: 80, systemImage: "person.3.fill")
                .overlay(alignment: .bottomTrailing) {
                    if model.isOwner {
                        Button { model.photoUpload.open() } label: {
                            Image(systemName: "camera.fill")
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor, in: .circle)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("chat_settings_group_photo_change"))
                    }
                }
            Text(verbatim: model.savedGroupTitle).font(.title3.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var form: some View {
        Form {
            if model.isGroup {
                Section { groupHeader }
                    .listRowBackground(Color.clear)
                Section("chat_settings_group_section") {
                    HStack {
                        TextField("chat_settings_group_title", text: $model.groupTitle, prompt: Text("chat_settings_group_title_placeholder"))
                            .disabled(!model.isOwner)
                        if model.isOwner, model.groupTitleChanged {
                            Button("chat_settings_save_group_title") { Task { await model.saveGroupTitle() } }
                                .disabled(model.isSavingGroupTitle)
                        }
                    }
                    NavigationLink("chat_settings_members", value: LoopRoute.groupMembers(conversationId: model.conversationId))
                }
            }
            Section {
                Toggle(isOn: Binding(get: { model.isMuted }, set: { value in Task { await model.setMuted(value) } })) {
                    Text("chat_settings_mute")
                    Text("chat_settings_mute_hint")
                }
                Toggle(isOn: Binding(get: { model.isPinned }, set: { value in Task { await model.setPinned(value) } })) {
                    Text("chat_settings_pin")
                    Text("chat_settings_pin_hint")
                }
            }
            Section("chat_settings_custom_title") {
                HStack {
                    TextField("chat_settings_custom_title", text: $model.customTitle, prompt: Text("chat_settings_custom_title_placeholder"))
                    if model.customTitleChanged {
                        Button("chat_settings_save_title") { Task { await model.saveCustomTitle() } }
                            .disabled(model.isSavingTitle)
                    }
                }
            }
            Section {
                PhotosPicker(selection: $wallpaperItem, matching: .images) { Text("chat_settings_wallpaper_pick") }
                if model.wallpaperPath != nil {
                    Button("chat_settings_wallpaper_clear", role: .destructive) { model.clearWallpaper() }
                }
            } header: {
                Text("chat_settings_wallpaper")
            } footer: {
                Text("chat_settings_wallpaper_hint")
            }
            if model.latestMessageId != nil {
                Section {
                    Button("chat_settings_mark_read") { Task { await model.markRead() } }
                        .disabled(model.isMarkingRead)
                } footer: {
                    Text("chat_settings_mark_read_hint")
                }
            }
            if model.isGroup {
                Section {
                    Button("chat_settings_leave", role: .destructive) { confirmingLeave = true }
                } footer: {
                    Text("chat_settings_leave_hint")
                }
            }
        }
    }
}
