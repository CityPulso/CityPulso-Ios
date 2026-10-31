import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import UniformTypeIdentifiers

/**
 * 输入栏（Android `ChatComposer`，参照 `.pictures/messages`）：左边语音 / 键盘切换，中间输入框或「按住 说话」，再是表情和「+」；
 * 有字时「+」换成发送。下面是正在引用的消息。表情按钮切到系统表情键盘。
 */
struct ChatComposer: View {
    @Bindable var model: ChatConversationModel
    let recorder: ChatVoiceRecorder
    @Environment(\.pulsoPalette) private var palette
    @State private var focused = false
    @State private var emoji = false
    @State private var cancelling = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: PulsoSpace.s1) {
                Button {
                    emoji = false
                    model.setComposerMode(model.composerMode == .voice ? .text : .voice)
                    focused = model.composerMode == .text
                } label: {
                    Image(systemName: model.composerMode == .voice ? "keyboard" : "mic").font(.title2).frame(width: 40, height: 40)
                }
                .accessibilityLabel(Text((model.composerMode == .voice ? "shell_chat_keyboard_mode" : "shell_chat_voice_mode") as LocalizedStringKey))
                if model.composerMode == .voice {
                    holdToTalk.padding(.vertical, 2)
                } else {
                    PulsoEmojiTextView(text: $model.draft, focused: $focused, emoji: emoji)
                        .padding(.horizontal, PulsoSpace.s3)
                        .padding(.vertical, 10)
                        .background(palette.background, in: palette.controlShape)
                        .padding(.vertical, 2)
                        .onChange(of: focused) { _, isFocused in if isFocused { model.panelOpen = false } }
                }
                // 表情：换成系统表情键盘；再点回到普通键盘（Android 表情面板）。
                Button {
                    if emoji {
                        emoji = false
                    } else {
                        if model.composerMode == .voice { model.setComposerMode(.text) }
                        model.panelOpen = false
                        emoji = true
                    }
                    focused = true
                } label: {
                    Image(systemName: emoji ? "keyboard" : "face.smiling").font(.title2).frame(width: 40, height: 40)
                }
                .accessibilityLabel(Text((emoji ? "shell_chat_keyboard_mode" : "shell_chat_emoji") as LocalizedStringKey))
                if model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.composerMode == .voice {
                    Button {
                        focused = false
                        emoji = false
                        model.togglePanel()
                    } label: {
                        Image(systemName: "plus.circle").font(.title2).frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(Text("shell_chat_plus"))
                } else {
                    Button("shell_chat_send") { Task { await model.sendText() } }
                        .buttonStyle(.pulso())
                        .environment(\.pulsoControlSize, .compact)
                        .padding(.horizontal, PulsoSpace.s1)
                        .padding(.bottom, PulsoSpace.s1)
                }
            }
            .tint(palette.text)
            .padding(.horizontal, PulsoSpace.s1)
            .padding(.vertical, PulsoSpace.s2)
            if let quoting = model.quoting {
                HStack {
                    ChatQuoteLine(quote: quoting.quote)
                    Spacer()
                    Button { model.clearQuote() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondaryText) }
                        .accessibilityLabel(Text("shell_chat_quote_remove"))
                }
                .padding(.horizontal, PulsoSpace.s3)
                .padding(.bottom, PulsoSpace.s2)
            }
            if model.panelOpen { ChatPlusPanel(model: model) }
        }
        .background(palette.gray.step(2))
        .overlay(alignment: .top) {
            if recorder.isRecording { recordingOverlay.offset(y: -150) }
        }
    }

    /** 按住说话：上滑松手取消（Android `HoldToTalkOverlay`）。 */
    private var holdToTalk: some View {
        Text((recorder.isRecording ? (cancelling ? "shell_chat_release_to_cancel" : "shell_chat_release_to_send") : "shell_chat_hold_to_talk") as LocalizedStringKey)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(recorder.isRecording ? palette.gray.step(5) : palette.background, in: palette.controlShape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !recorder.isRecording {
                            Task {
                                if await !recorder.start() { PulsoMessageCenter.shared.info("shell_chat_voice_mic_needed") }
                            }
                        }
                        cancelling = value.translation.height < -60
                    }
                    .onEnded { _ in
                        let cancel = cancelling
                        cancelling = false
                        guard recorder.isRecording else { return }
                        if let (file, duration) = recorder.stop(send: !cancel) {
                            Task { await model.sendVoice(file, durationMs: duration) }
                        } else if !cancel {
                            PulsoMessageCenter.shared.info("shell_chat_voice_too_short")
                        }
                    }
            )
    }

    private var recordingOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: cancelling ? "xmark.circle" : "mic.fill").font(.largeTitle)
            Text((cancelling ? "shell_chat_release_to_cancel" : "shell_chat_release_to_send") as LocalizedStringKey).font(.caption)
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(cancelling ? Color.red.opacity(0.85) : Color.black.opacity(0.7), in: .rect(cornerRadius: 12))
    }
}

/** 「+」面板（参照 more_tool.jpg）：圆角白块 + 图标 + 名字，四列。 */
private struct ChatPlusPanel: View {
    let model: ChatConversationModel
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var importingFile = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 18) {
            PhotosPicker(selection: $photoItem, matching: .images) { PlusTile(symbol: "photo", label: "shell_chat_plus_image") }
            PhotosPicker(selection: $videoItem, matching: .videos) { PlusTile(symbol: "video", label: "shell_chat_plus_video") }
            Button { importingFile = true } label: { tile("doc", "shell_chat_plus_file") }
            Button { shell?.push(NearRoute.chatLocationPick(conversationId: model.conversationId)) } label: { tile("mappin.and.ellipse", "shell_chat_plus_location") }
            Button { shell?.push(NearRoute.chatActivityPicker(conversationId: model.conversationId, hosted: true)) } label: { tile("calendar.badge.plus", "shell_chat_plus_hosted_activities") }
            Button { shell?.push(NearRoute.chatActivityPicker(conversationId: model.conversationId, hosted: false)) } label: { tile("calendar", "shell_chat_plus_joined_activities") }
            Button { shell?.push(NearRoute.chatFavoritePicker(conversationId: model.conversationId)) } label: { tile("heart", "shell_chat_plus_favorites") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await send(item, type: .image, fallbackMime: "image/jpeg") }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            videoItem = nil
            Task { await send(item, type: .video, fallbackMime: "video/mp4") }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item]) { result in
            guard case let .success(url) = result else { return }
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    PulsoMessageCenter.shared.error("shell_chat_attachment_unreadable")
                    return
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                await model.sendAttachment(data, fileName: url.lastPathComponent, mimeType: mime, type: .file)
            }
        }
    }

    private func send(_ item: PhotosPickerItem, type: AssetType, fallbackMime: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            PulsoMessageCenter.shared.error("shell_chat_attachment_unreadable")
            return
        }
        let contentType = item.supportedContentTypes.first
        let ext = contentType?.preferredFilenameExtension ?? (type == .video ? "mp4" : "jpg")
        await model.sendAttachment(data, fileName: "chat-\(Int(Date().timeIntervalSince1970)).\(ext)", mimeType: contentType?.preferredMIMEType ?? fallbackMime, type: type)
    }

    private func tile(_ symbol: String, _ label: LocalizedStringKey) -> PlusTile { PlusTile(symbol: symbol, label: label) }
}

/** 「+」面板的一格；单独的 View，PhotosPicker 的（非隔离）label 闭包也能建。 */
private struct PlusTile: View {
    let symbol: String
    let label: LocalizedStringKey

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 60, height: 60)
                .background(palette.background, in: palette.cardShape)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
