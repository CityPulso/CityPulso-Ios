import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 会话列表的一行（Android `ConversationRowUi`）。 */
struct ConversationRowUi: Identifiable, Hashable {
    let conversationId: String
    let isGroup: Bool
    let title: String
    let avatarURL: URL?
    let preview: String?
    /** 最后一条消息的类型：媒体和卡片在预览前（或代替预览）加一个标签。 */
    let previewType: MessageType
    let lastMessageAt: String?
    let isMuted: Bool
    let pinnedAt: String?

    var id: String { conversationId }
}

/**
 * 私聊 / 群聊列表行（Android `ConversationRows`），离线优先；消息页和转发选择共用。
 * 对方的昵称和头像来自缓存的资料卡，缺的一次批量拉。
 */
@MainActor
@Observable
final class ConversationRows {
    private(set) var direct = Loadable<[ConversationRowUi]>()
    private(set) var group = Loadable<[ConversationRowUi]>()

    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var directItems = Loadable<[ConversationDirectItem]>()
    @ObservationIgnored private var cards: [String: ProfileCard] = [:]

    func observe() async {
        let session = sessionStore.state.value
        let key = ConversationListKey(accountId: session.currentAccountId, profileId: session.currentProfileId)
        await concurrently([
            {
                var cardsTask: Task<Void, Never>?
                var peers: [String] = []
                for await response in self.communicationService.streamDirectConversations(key) {
                    self.directItems = self.directItems.reduce(response)
                    self.publishDirect()
                    let next = Array(Set((self.directItems.data ?? []).map(\.peerProfileId))).sorted()
                    guard next != peers else { continue }
                    peers = next
                    cardsTask?.cancel()
                    // 缓存里有的卡马上显示；缺的批量拉回来再填上。
                    cardsTask = Task {
                        Task { try? await self.authService.ensureProfileCards(next) }
                        for await cards in self.authService.observeProfileCards(next) {
                            self.cards = cards
                            self.publishDirect()
                        }
                    }
                }
                cardsTask?.cancel()
            },
            {
                var items = Loadable<[ConversationGroupItem]>()
                for await response in self.communicationService.streamGroupConversations(key) {
                    items = items.reduce(response)
                    self.group = Loadable(data: items.data.map { $0.map(self.groupRow) }, isLoading: items.isLoading, error: items.error)
                }
            },
        ])
    }

    func refresh() {
        communicationService.refreshConversations()
    }

    private func publishDirect() {
        direct = Loadable(data: directItems.data.map { $0.map { self.directRow($0, self.cards[$0.peerProfileId]) } }, isLoading: directItems.isLoading, error: directItems.error)
    }

    private func directRow(_ item: ConversationDirectItem, _ card: ProfileCard?) -> ConversationRowUi {
        let name = card?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(item.peerProfileId.prefix(8))
        return ConversationRowUi(
            conversationId: item.conversationId,
            isGroup: false,
            title: item.customTitle.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? name,
            avatarURL: ImageURLs.image(card?.avatarImageId, base: config.apiBaseURL),
            preview: item.lastMessagePreview,
            previewType: MessageType.fromWire(item.lastMessageType),
            lastMessageAt: item.lastMessageAt,
            isMuted: item.isMuted,
            pinnedAt: item.pinnedAt
        )
    }

    private func groupRow(_ item: ConversationGroupItem) -> ConversationRowUi {
        let title = item.customTitle.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? item.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? String(item.conversationId.prefix(8))
        return ConversationRowUi(
            conversationId: item.conversationId,
            isGroup: true,
            title: title,
            avatarURL: ImageURLs.image(item.avatarImageId, base: config.apiBaseURL),
            preview: item.lastMessagePreview,
            previewType: MessageType.fromWire(item.lastMessageType),
            lastMessageAt: item.lastMessageAt,
            isMuted: item.isMuted,
            pinnedAt: item.pinnedAt
        )
    }
}

/** 会话下面那一行：文字消息显示文字；媒体显示「[图片]」；卡片和位置是「[活动] 周六双打」。 */
func conversationPreview(_ row: ConversationRowUi) -> String? {
    let text = row.preview?.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = (text?.isEmpty ?? true) ? nil : text
    let kind: String.LocalizationValue
    switch row.previewType {
    case .image: kind = "shell_chat_plus_image"
    case .video: kind = "shell_chat_plus_video"
    case .audio: kind = "shell_chat_voice_message"
    case .file: kind = "shell_chat_plus_file"
    case .location: kind = "shell_chat_plus_location"
    case .eventShare: kind = "shell_chat_card_kind_event"
    case .venueShare: kind = "shell_chat_card_kind_venue"
    case .forumShare: kind = "shell_chat_card_kind_forum"
    case .postShare: kind = "shell_chat_card_kind_post"
    case .buildingShare: kind = "shell_chat_card_kind_building"
    case .text, .system: return body
    }
    let tag = localizedFormat("shell_chat_hub_preview_kind", String(localized: kind))
    return body.map { "\(tag) \($0)" } ?? tag
}

/** 一行会话：头像（群没有头像时是群图标）、标题、预览。 */
struct ConversationRowView: View {
    let row: ConversationRowUi

    var body: some View {
        HStack(spacing: 14) {
            if row.isGroup, row.avatarURL == nil {
                PulsoAvatar(url: nil, size: 48, systemImage: "person.3.fill")
            } else {
                PulsoAvatar(url: row.avatarURL, size: 48, fallbackText: row.title)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let preview = conversationPreview(row) {
                    Text(verbatim: preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
