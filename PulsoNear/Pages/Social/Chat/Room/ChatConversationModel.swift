import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI

struct ChatSenderUi: Hashable, Sendable {
    let profileId: String
    let displayName: String
    let avatarURL: URL?
}

/** 气泡显示的文件附件。 */
struct ChatFileUi: Hashable {
    let name: String
    let sizeBytes: Int?
    let url: URL?
}

/** 被引用的那条消息；媒体没有文字，显示类型。 */
struct ChatQuoteUi: Hashable {
    let senderName: String?
    let type: MessageType
    let preview: String
}

/** 一个气泡（Android `ChatMessageRowUi`）。 */
struct ChatMessageRowUi: Identifiable, Hashable {
    let messageId: String
    let senderId: String
    let isMine: Bool
    let type: MessageType
    let text: String
    let createdAtMillis: Double
    let status: ChatMessageStatus
    let imageURL: URL?
    let videoURL: URL?
    let audioURL: URL?
    /** 语音或视频的时长；发的人没记录时 nil。 */
    let durationMs: Int?
    let file: ChatFileUi?
    let location: ChatLocationContent?
    /** 分享卡片，图片已经是地址。 */
    let sharedCard: ChatSharedCardContent?
    /** 活动的发起人自己发的活动卡片。 */
    let hostedCard: Bool
    let sender: ChatSenderUi?
    let quote: ChatQuoteUi?
    let deleted: Bool
    /** 原始内容，转发时原样再发。 */
    let content: ChatMessageContent
    let attachments: [ChatAttachment]

    var id: String { messageId }
    var isSent: Bool { status == .sent }

    /** 长按菜单；空 = 没有菜单。 */
    var actions: [ChatMessageAction] {
        guard !deleted, type != .system, isSent else { return [] }
        var out: [ChatMessageAction] = []
        if type == .text { out.append(.copy) }
        out.append(.forward)
        out.append(.quote)
        if isMine { out.append(.unsend) }
        return out
    }
}

/** 输入框上面正在引用的消息。 */
struct ChatQuoteDraft: Hashable {
    let messageId: String
    let senderId: String
    let quote: ChatQuoteUi
}

extension MessageType {
    /** 分享卡片类消息。 */
    var isShareCard: Bool {
        switch self {
        case .eventShare, .venueShare, .buildingShare, .postShare, .forumShare: true
        default: false
        }
    }
}

/**
 * 聊天室（Android `ChatConversationViewModel`）：本地历史为准、网络刷新；发消息先显示乐观行再发；
 * 图片 / 视频 / 文件 / 语音上传后发；引用、转发、撤回；别的页面选好的位置和卡片经 [ChatShareDraftStore] 发进来。
 */
@MainActor
@Observable
final class ChatConversationModel {
    private static let pageSize = 50

    let conversationId: String
    let isGroup: Bool
    var draft = ""
    var composerMode = ChatComposerMode.text
    var panelOpen = false
    private(set) var quoting: ChatQuoteDraft?
    var forwarding: ChatMessageRowUi?
    private(set) var isLoading = true
    private(set) var isSending = false
    private(set) var loadingOlder = false
    private(set) var nextCursor: String?
    /** 只在第一次加载失败且本地什么都没有时用；发送失败走全局提示。 */
    private(set) var loadError: UiError?
    private(set) var wallpaperPath: String?
    private(set) var map = ResolvedMapPreference()
    private(set) var rows: [ChatMessageRowUi] = []
    let forwardTargets = ConversationRows()

    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.chatLocalRepository) private var local
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.assetRepository) private var assets
    @ObservationIgnored @Injected(\.chatWallpaperStore) private var wallpapers
    @ObservationIgnored @Injected(\.chatShareDraftStore) private var shareDrafts
    @ObservationIgnored @Injected(\.communicationEventBus) private var communicationBus
    @ObservationIgnored @Injected(\.preferenceService) private var preferenceService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var stored: [StoredChatMessage] = []
    @ObservationIgnored private var senders: [String: ChatSenderUi] = [:]
    /** 已经报过已读的最新一条；重新加载没有更新的就不再报。 */
    @ObservationIgnored private var lastReadMessageId: String?

    init(conversationId: String, isGroup: Bool) {
        self.conversationId = conversationId
        self.isGroup = isGroup
    }

    private var myProfileId: String { sessionStore.state.value.currentProfileId }
    private var conversationType: ConversationType { isGroup ? .group : .direct }

    /* ------------------------------ 订阅 ------------------------------ */

    func observe() async {
        await concurrently([
            {
                for await messages in self.local.observe(self.conversationId) {
                    self.stored = messages
                    self.publish()
                }
            },
            {
                for await draft in self.shareDrafts.events() where draft.conversationId == self.conversationId {
                    let (type, content) = draft.message
                    await self.sendNow(type: type, content: content)
                }
            },
            {
                for await _ in self.communicationBus.signals(where: { $0 == .invalidateConversations }) {
                    await self.reloadLatest(force: true)
                }
            },
            {
                for await paths in self.wallpapers.paths.values() {
                    self.wallpaperPath = paths[self.conversationId]
                }
            },
            {
                for await preference in self.preferenceService.preference.values() {
                    self.map = preference.map
                }
            },
            { await self.forwardTargets.observe() },
            { await self.reloadLatest(force: true) },
        ])
    }

    /** 标题：我给这个会话的备注，否则对方的名字 / 群名。 */
    var title: String? { allConversations.first { $0.conversationId == conversationId }?.title }

    /** 全部会话（转发目标），最近有消息的在前。 */
    var allConversations: [ConversationRowUi] {
        ((forwardTargets.direct.data ?? []) + (forwardTargets.group.data ?? [])).sorted { ($0.lastMessageAt ?? "") > ($1.lastMessageAt ?? "") }
    }

    func retry() async {
        isLoading = true
        loadError = nil
        await reloadLatest(force: true)
    }

    func loadOlder() async {
        guard let cursor = nextCursor, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await communicationService.freshMessages(messagesKey(cursor))
            try await local.upsertRemote(page.items)
            await resolveSenders(page.items)
            nextCursor = page.nextCursor
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_load_older_failed")
        }
    }

    private func reloadLatest(force: Bool) async {
        do {
            let page = try await force ? communicationService.freshMessages(messagesKey(nil)) : communicationService.getMessages(messagesKey(nil))
            try await local.upsertRemote(page.items)
            await resolveSenders(page.items)
            // 标已读会刷新会话列表，又会重拉这一页；只报更新的一条，避免来回循环。
            if let last = page.items.max(by: { $0.createdAt < $1.createdAt }), last.messageId != lastReadMessageId {
                lastReadMessageId = last.messageId
                try? await communicationService.markConversationRead(conversationType, conversationId, MarkReadRequest(messageId: last.messageId))
            }
            isLoading = false
            loadError = nil
            nextCursor = page.nextCursor
        } catch {
            // 本地历史照样显示；本地也没有时才显示错误页。
            isLoading = false
            loadError = UiError(error)
        }
    }

    /** 每个发送者的昵称和头像，来自共用的资料卡缓存（Android `ChatSenderDirectory`）。 */
    private func resolveSenders(_ items: [ChatMessageItem]) async {
        let me = profileStore.current.value
        if let myId = me?.profileId { try? await authService.cacheProfileCard(myId, displayName: me?.displayName, avatarImageId: me?.avatarImageId) }
        let ids = Array(Set([me?.profileId].compactMap { $0 } + items.map(\.senderId)))
        try? await authService.ensureProfileCards(ids)
        var cards: [String: ProfileCard] = [:]
        for await value in authService.observeProfileCards(ids) {
            cards = value
            break
        }
        for id in ids {
            let card = cards[id]
            senders[id] = ChatSenderUi(
                profileId: id,
                displayName: card?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(id.prefix(8)),
                avatarURL: ImageURLs.image(card?.avatarImageId, base: config.apiBaseURL)
            )
        }
        publish()
    }

    private func publish() {
        let myId = myProfileId
        rows = stored.map { row($0, myId: myId) }
    }

    private func row(_ message: StoredChatMessage, myId: String) -> ChatMessageRowUi {
        let item = message.item
        let attachments = item.attachments ?? []
        let image = attachments.first { $0.type == .image }
        let video = attachments.first { $0.type == .video }
        let audio = attachments.first { $0.type == .audio }
        let file = attachments.first { $0.type == .file }
        let base = config.apiBaseURL
        var shared = item.type.isShareCard ? item.content.shared : nil
        if let key = shared?.imageKey { shared?.imageKey = ImageURLs.image(key, base: base)?.absoluteString ?? key }
        let hosted = item.type == .eventShare && shared?.hostProfileId != nil && shared?.hostProfileId == item.senderId
        return ChatMessageRowUi(
            messageId: item.messageId,
            senderId: item.senderId,
            isMine: item.senderId == myId,
            type: item.type,
            text: item.content.text ?? "",
            createdAtMillis: message.createdAtMillis,
            status: message.status,
            imageURL: ImageURLs.attachment(image?.assetId, type: .image, base: base),
            videoURL: ImageURLs.attachment(video?.assetId, type: .video, base: base),
            audioURL: ImageURLs.attachment(audio?.assetId, type: .audio, base: base),
            durationMs: (audio ?? video)?.durationMs,
            file: file.map { ChatFileUi(name: $0.fileName ?? "", sizeBytes: $0.fileSize, url: ImageURLs.attachment($0.assetId, type: .file, base: base)) },
            location: item.content.location,
            sharedCard: shared,
            hostedCard: hosted,
            sender: senders[item.senderId],
            quote: item.replyTo.map { ChatQuoteUi(senderName: senders[$0.senderId]?.displayName, type: $0.type, preview: $0.preview ?? "") },
            deleted: !(item.deletedAt ?? "").isEmpty,
            content: item.content,
            attachments: attachments
        )
    }

    private func messagesKey(_ cursor: String?) -> ConversationMessagesKey {
        let session = sessionStore.state.value
        return ConversationMessagesKey(
            accountId: session.currentAccountId, profileId: session.currentProfileId,
            conversationType: conversationType, conversationId: conversationId, limit: Self.pageSize, cursor: cursor
        )
    }

    /* ------------------------------ 输入 ------------------------------ */

    func setComposerMode(_ mode: ChatComposerMode) {
        composerMode = mode
        panelOpen = false
    }

    /** 开 / 关「+」面板；打开时退出语音模式。 */
    func togglePanel() {
        panelOpen.toggle()
        composerMode = .text
    }

    func quote(_ message: ChatMessageRowUi) {
        quoting = ChatQuoteDraft(
            messageId: message.messageId, senderId: message.senderId,
            quote: ChatQuoteUi(senderName: message.sender?.displayName, type: message.type, preview: message.text)
        )
        composerMode = .text
    }

    func clearQuote() {
        quoting = nil
    }

    func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let quote = quoting
        draft = ""
        quoting = nil
        await sendNow(type: .text, content: ChatMessageContent(text: text), quoting: quote)
    }

    /** 上传选好的图片 / 视频 / 文件再发。 */
    func sendAttachment(_ data: Data, fileName: String, mimeType: String, type: AssetType) async {
        panelOpen = false
        isSending = true
        defer { isSending = false }
        do {
            let assetId = try await assets.uploadChatAsset(data, fileName: fileName, mimeType: mimeType, type: type)
            let (messageType, attachmentType): (MessageType, AttachmentType) = switch type {
            case .video: (.video, .video)
            case .audio: (.audio, .audio)
            case .file: (.file, .file)
            case .image: (.image, .image)
            }
            let attachment = ChatAttachment(attachmentId: UUID().uuidString, type: attachmentType, assetId: assetId, fileName: fileName, fileSize: data.count)
            await sendNow(type: messageType, content: ChatMessageContent(), attachments: [attachment])
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_send_failed")
        }
    }

    /** 录好的语音：上传后发，录音文件不管成败都删掉。 */
    func sendVoice(_ file: URL, durationMs: Int) async {
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            let data = try Data(contentsOf: file)
            let assetId = try await assets.uploadChatAsset(data, fileName: file.lastPathComponent, mimeType: "audio/mp4", type: .audio)
            let attachment = ChatAttachment(attachmentId: UUID().uuidString, type: .audio, assetId: assetId, fileName: file.lastPathComponent, fileSize: data.count, durationMs: durationMs)
            await sendNow(type: .audio, content: ChatMessageContent(), attachments: [attachment])
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_send_failed")
        }
    }

    /** 先显示（乐观行）再发；服务端那条在重拉时替换它。失败时气泡留着标成失败，全局提示说原因。 */
    private func sendNow(type: MessageType, content: ChatMessageContent, attachments: [ChatAttachment] = [], quoting: ChatQuoteDraft? = nil) async {
        let clientId = UUID().uuidString
        let reply = quoting.map { ChatReplyReference(messageId: $0.messageId, senderId: $0.senderId, type: $0.quote.type, preview: $0.quote.preview) }
        let optimistic = ChatMessageItem(
            conversationId: conversationId, messageId: clientId, clientMessageId: clientId, senderId: myProfileId,
            type: type, content: content, replyTo: reply, attachments: attachments.isEmpty ? nil : attachments,
            createdAt: DateTimeFormatters.rfc3339(Date())
        )
        try? await local.upsertOptimistic(optimistic)
        do {
            try await communicationService.sendChatMessage(SendMessageRequest(
                conversationType: conversationType, conversationId: conversationId, type: type, content: content,
                clientMessageId: clientId, replyToMessageId: quoting?.messageId, attachments: attachments.isEmpty ? nil : attachments
            ))
            await reloadLatest(force: true)
        } catch {
            try? await local.markFailed(clientId)
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_send_failed")
        }
    }

    /* ------------------------------ 消息操作 ------------------------------ */

    func forward(to target: ConversationRowUi) async {
        guard let message = forwarding else { return }
        forwarding = nil
        do {
            try await communicationService.sendChatMessage(SendMessageRequest(
                conversationType: target.isGroup ? .group : .direct,
                conversationId: target.conversationId,
                type: message.type,
                content: message.content,
                clientMessageId: UUID().uuidString,
                // 同样的文件，在目标会话里是新的附件行。
                attachments: message.attachments.isEmpty ? nil : message.attachments.map { var copy = $0; copy.attachmentId = UUID().uuidString; return copy }
            ))
            PulsoMessageCenter.shared.success("shell_chat_forwarded")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_forward_failed")
        }
    }

    func unsend(_ message: ChatMessageRowUi) async {
        do {
            try await communicationService.deleteChatMessage(DeleteMessageRequest(messageId: message.messageId, conversationType: conversationType, conversationId: conversationId))
            try await local.markDeleted(message.messageId, deletedAt: DateTimeFormatters.rfc3339(Date()))
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_chat_unsend_failed")
        }
    }
}
