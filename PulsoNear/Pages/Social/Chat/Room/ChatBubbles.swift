import AVKit
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一个气泡点了以后要做的事（页面决定去哪）。 */
struct ChatBubbleCallbacks {
    var onLongPress: (ChatMessageRowUi) -> Void
    var onImage: (URL) -> Void
    var onVideo: (URL) -> Void
    var onLocation: (ChatLocationContent) -> Void
    var onCard: (MessageType, ChatSharedCardContent) -> Void
    var onBook: (ChatSharedCardContent) -> Void
    var onOpenProfile: (String) -> Void
}

private let bubbleMaxWidth: CGFloat = 260
private let avatarSize: CGFloat = 40

/**
 * 一条消息（Android `ChatMessageBubble`，参照 `.pictures/messages`）：方形头像 + 带小尾巴的气泡（我的是主色、对方白色）；
 * 系统消息和撤回是居中的灰字；群聊里对方名字在气泡上面。
 */
struct ChatMessageBubble: View {
    let message: ChatMessageRowUi
    let isGroup: Bool
    let player: ChatAudioPlayer
    let map: ResolvedMapPreference
    let callbacks: ChatBubbleCallbacks

    var body: some View {
        if message.type == .system {
            ChatCenterNote(text: chatSystemNoticeText(message.content.system, mine: message.isMine))
        } else if message.deleted {
            ChatCenterNote(text: message.isMine
                ? String(localized: "shell_chat_unsent_mine")
                : localizedFormat("shell_chat_unsent_peer", message.sender?.displayName ?? String(localized: "shell_chat_peer_fallback")))
        } else {
            HStack(alignment: .top, spacing: 8) {
                if message.isMine { Spacer(minLength: avatarSize + 8) } else { avatar }
                VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
                    if isGroup, !message.isMine {
                        Text(verbatim: message.sender?.displayName ?? "").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .center, spacing: 6) {
                        if message.isMine, message.status == .failed {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                                .accessibilityLabel(Text("shell_chat_status_failed"))
                        }
                        if message.isMine, message.status == .sending { ProgressView().controlSize(.mini) }
                        content
                            .onLongPressGesture { if !message.actions.isEmpty { callbacks.onLongPress(message) } }
                    }
                    if let quote = message.quote { ChatQuoteLine(quote: quote) }
                }
                if message.isMine { avatar } else { Spacer(minLength: avatarSize + 8) }
            }
            .padding(.horizontal, 12)
        }
    }

    private var avatar: some View {
        Button { callbacks.onOpenProfile(message.senderId) } label: {
            PulsoRemoteImage(url: message.sender?.avatarURL)
                .overlay {
                    if message.sender?.avatarURL == nil {
                        Text(verbatim: String((message.sender?.displayName ?? "?").prefix(1))).font(.headline).foregroundStyle(.white)
                    }
                }
                .frame(width: avatarSize, height: avatarSize)
                .background(Color.accentColor.opacity(0.5))
                .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch message.type {
        case .image:
            if let url = message.imageURL {
                Button { callbacks.onImage(url) } label: {
                    PulsoRemoteImage(url: url).frame(maxWidth: 180, maxHeight: 240).frame(width: 180, height: 200).clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        case .video:
            if let url = message.videoURL {
                Button { callbacks.onVideo(url) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.85))
                        Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                    }
                    .frame(width: 180, height: 120)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("shell_chat_plus_video"))
            }
        case .audio:
            if let url = message.audioURL { voice(url) }
        case .file:
            if let file = message.file { fileCard(file) }
        case .location:
            if let location = message.location { locationCard(location) }
        case .eventShare, .venueShare, .buildingShare, .postShare, .forumShare:
            if let card = message.sharedCard { ChatShareCard(type: message.type, card: card, mine: message.isMine, hosted: message.hostedCard, callbacks: callbacks) }
        case .text, .system:
            bubble {
                Text(verbatim: message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(message.isMine ? Color.white : Color.primary)
            .background(ChatBubbleShape(mine: message.isMine).fill(message.isMine ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
    }

    private func voice(_ url: URL) -> some View {
        let playing = player.playingURL == url
        let seconds = max(1, (message.durationMs ?? 0) / 1000)
        // 越长的语音气泡越宽（Android 同样按时长伸展）。
        let width = min(bubbleMaxWidth, 70 + CGFloat(min(seconds, 60)) * 3)
        return Button { player.toggle(url) } label: {
            bubble {
                HStack {
                    if message.isMine { Spacer(minLength: 0) }
                    if !message.isMine { Image(systemName: playing ? "stop.fill" : "waveform") }
                    Text(verbatim: localizedFormat("shell_chat_voice_duration", seconds))
                    if message.isMine { Image(systemName: playing ? "stop.fill" : "waveform") }
                    if !message.isMine { Spacer(minLength: 0) }
                }
                .frame(width: width)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text((playing ? "shell_chat_voice_stop" : "shell_chat_voice_play") as LocalizedStringKey))
    }

    @ViewBuilder
    private func fileCard(_ file: ChatFileUi) -> some View {
        let row = HStack(spacing: 10) {
            Image(systemName: "doc.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name.isEmpty ? String(localized: "shell_chat_plus_file") : file.name).lineLimit(2)
                if let size = file.sizeBytes {
                    Text(Int64(size), format: .byteCount(style: .file)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 220, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))
        if let url = file.url { Link(destination: url) { row }.buttonStyle(.plain) } else { row }
    }

    private func locationCard(_ location: ChatLocationContent) -> some View {
        Button { callbacks.onLocation(location) } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: location.label ?? location.address ?? String(localized: "shell_chat_plus_location")).font(.subheadline.weight(.medium)).lineLimit(1)
                    if let address = location.address, address != location.label {
                        Text(verbatim: address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(10)
                NearMapView(map: map, initialCenter: (location.latitude, location.longitude), initialZoom: 15)
                    .allowsHitTesting(false)
                    .frame(height: 110)
                    .overlay { Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red) }
            }
            .frame(width: 240)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/** 带小尾巴的气泡（Android `ChatBubbleShape`）：尾巴在头像一侧、靠上。 */
struct ChatBubbleShape: Shape {
    let mine: Bool

    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 6
        let body = mine ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height)
            : CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: 6)
        let y: CGFloat = min(20, rect.height / 2)
        if mine {
            path.move(to: CGPoint(x: body.maxX, y: y - 6))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.addLine(to: CGPoint(x: body.maxX, y: y + 6))
        } else {
            path.move(to: CGPoint(x: body.minX, y: y - 6))
            path.addLine(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: body.minX, y: y + 6))
        }
        return path
    }
}

/** 居中的灰字：系统消息、撤回、时间分隔（参照图里的灰底小标签）。 */
struct ChatCenterNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: .rect(cornerRadius: 4))
            .frame(maxWidth: .infinity)
    }
}

/** 气泡下面引用的那条（Android `ChatQuote`）。 */
struct ChatQuoteLine: View {
    let quote: ChatQuoteUi

    var body: some View {
        Text(verbatim: localizedFormat("shell_chat_quote_line", quote.senderName ?? String(localized: "shell_chat_peer_fallback"), quotePreview(quote)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: .rect(cornerRadius: 4))
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

/** 引用里显示的文字：文字消息是原文，媒体和卡片是类型名。 */
func quotePreview(_ quote: ChatQuoteUi) -> String {
    let row = ConversationRowUi(conversationId: "", isGroup: false, title: "", avatarURL: nil, preview: quote.preview, previewType: quote.type, lastMessageAt: nil, isMuted: false, pinnedAt: nil)
    return conversationPreview(row) ?? ""
}

/** 分享卡片（Android `bubbles/cards` 下的卡片）：封面、类型、标题、副标题和按钮；我发的在主色上。 */
struct ChatShareCard: View {
    let type: MessageType
    let card: ChatSharedCardContent
    let mine: Bool
    let hosted: Bool
    let callbacks: ChatBubbleCallbacks

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = card.imageKey, let url = URL(string: image), type != .postShare {
                PulsoRemoteImage(url: url).frame(height: type == .eventShare || type == .venueShare ? 140 : 96).clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label { Text(kindLabel) } icon: { Image(systemName: kindSymbol) }
                        .font(.caption.weight(.medium))
                        .opacity(0.8)
                    if hosted {
                        Text("shell_chat_card_hosted").font(.caption2.weight(.semibold)).padding(.horizontal, 6).background(.white.opacity(0.25), in: .capsule)
                    }
                }
                Text(verbatim: card.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if type == .eventShare, let when = card.subtitle.flatMap(cardWhen) ?? card.subtitle, !when.isEmpty {
                    Text(verbatim: when).font(.caption).opacity(0.8).lineLimit(1)
                } else if type != .postShare, let subtitle = card.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle).font(.caption).opacity(0.8).lineLimit(2)
                }
                HStack {
                    Button(primaryLabel) { callbacks.onCard(type, card) }
                        .buttonStyle(.pulso(.soft))
                        .tint(mine ? .white : .accentColor)
                    if type == .venueShare {
                        Button("shell_chat_card_book") { callbacks.onBook(card) }
                            .buttonStyle(.pulso())
                            .tint(mine ? .white.opacity(0.3) : .accentColor)
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
        }
        .frame(width: 260, alignment: .leading)
        .foregroundStyle(mine ? Color.white : Color.primary)
        .background(mine ? Color.accentColor : Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var kindLabel: LocalizedStringKey {
        switch type {
        case .eventShare: "shell_chat_card_kind_event"
        case .venueShare: "shell_chat_card_kind_venue"
        case .buildingShare: "shell_chat_card_kind_building"
        case .forumShare: "shell_chat_card_kind_forum"
        default:
            if let forum = card.subtitle, !forum.isEmpty { LocalizedStringKey(localizedFormat("shell_chat_card_post_in", forum)) } else { "shell_chat_card_kind_post" }
        }
    }

    private var kindSymbol: String {
        switch type {
        case .eventShare: "calendar"
        case .venueShare: "storefront"
        case .buildingShare: "building.2"
        case .forumShare: "text.bubble"
        default: "doc.text"
        }
    }

    private var primaryLabel: LocalizedStringKey {
        switch type {
        case .eventShare: "shell_chat_card_view_and_join"
        case .venueShare: "shell_chat_card_view_details"
        case .buildingShare: "shell_chat_card_view_building"
        case .forumShare: "shell_chat_card_enter"
        default: "shell_chat_card_view_post"
        }
    }

    /** 活动卡片第二行：开始时间（本地时区、本地格式）；读不了时 nil（Android `chatCardWhen`）。 */
    private func cardWhen(_ startsAt: String) -> String? {
        DateTimeFormatters.parseInstant(startsAt).map { $0.formatted(date: .abbreviated, time: .shortened) }
    }
}

/** 图片全屏（Android `ChatImageViewer`）：捏合缩放，点关闭。 */
struct ChatImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            PulsoRemoteImage(url: url, contentMode: .fit)
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = max(1, scale) } })
                .onTapGesture { dismiss() }
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white) }
                .padding()
                .accessibilityLabel(Text("pulso_ui_cancel", bundle: .pulsoLinkUI))
        }
    }
}

/** 视频全屏播放。 */
struct ChatVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
            .onDisappear { player?.pause() }
    }
}
