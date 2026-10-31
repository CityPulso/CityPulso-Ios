import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 消息之间隔这么久才在上面画一个时间。 */
private let chatTimeGapMs: Double = 5 * 60_000

/**
 * 聊天室（Android `ChatConversationScreen`，参照 `.pictures/messages`）：壁纸、消息（最新的在底部，滑到顶加载更早的）、
 * 时间分隔、长按出深色操作条（复制 / 转发 / 引用 / 撤回），输入栏；右上角进聊天设置。
 */
struct ChatConversationView: View {
    @State private var model: ChatConversationModel
    @State private var player = ChatAudioPlayer()
    @State private var recorder = ChatVoiceRecorder()
    @State private var actionsFor: ChatMessageRowUi?
    @State private var unsending: ChatMessageRowUi?
    @State private var viewingImage: URL?
    @State private var playingVideo: URL?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(conversationId: String, isGroup: Bool) {
        _model = State(initialValue: ChatConversationModel(conversationId: conversationId, isGroup: isGroup))
    }

    var body: some View {
        VStack(spacing: 0) {
            messages
            ChatComposer(model: model, recorder: recorder)
        }
        .background { wallpaper }
        .navigationTitle(Text(verbatim: model.title ?? String(localized: "shell_chat_conversation_title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NearRoute.chatSettings(conversationId: model.conversationId, isGroup: model.isGroup)) {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(Text("chat_settings_title"))
            }
        }
        .task { await model.observe() }
        .onDisappear { player.stop() }
        .sheet(item: $actionsFor) { message in actionBar(message) }
        .sheet(item: $unsending) { message in unsendSheet(message) }
        .sheet(item: Binding(get: { model.forwarding }, set: { model.forwarding = $0 })) { _ in forwardSheet }
        .fullScreenCover(item: Binding(get: { viewingImage.map(IdentifiedURL.init) }, set: { viewingImage = $0?.url })) { ChatImageViewer(url: $0.url) }
        .fullScreenCover(item: Binding(get: { playingVideo.map(IdentifiedURL.init) }, set: { playingVideo = $0?.url })) { ChatVideoPlayer(url: $0.url) }
    }

    @ViewBuilder
    private var wallpaper: some View {
        if let path = model.wallpaperPath, let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var messages: some View {
        let ordered = Array(model.rows.reversed())
        if ordered.isEmpty, let error = model.loadError {
            PulsoLoadErrorView(error) { Task { await model.retry() } }.frame(maxHeight: .infinity)
        } else if ordered.isEmpty, model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if ordered.isEmpty {
            ContentUnavailableView("shell_chat_conversation_empty", systemImage: "bubble.left.and.bubble.right").frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.loadingOlder { ProgressView() }
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || message.createdAtMillis - ordered[index - 1].createdAtMillis >= chatTimeGapMs {
                            ChatCenterNote(text: chatTimeLabel(message.createdAtMillis))
                        }
                        ChatMessageBubble(message: message, isGroup: model.isGroup, player: player, map: model.map, callbacks: callbacks)
                            .onAppear { if index == 0 { Task { await model.loadOlder() } } }
                    }
                }
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { model.panelOpen = false }
        }
    }

    private var callbacks: ChatBubbleCallbacks {
        ChatBubbleCallbacks(
            onLongPress: { actionsFor = $0 },
            onImage: { viewingImage = $0 },
            onVideo: { playingVideo = $0 },
            onLocation: { shell?.push(NearRoute.chatLocationView(latitude: $0.latitude, longitude: $0.longitude, label: $0.label, address: $0.address)) },
            onCard: { type, card in
                // 娱邻的卡片交给娱邻（没装就开网站）。
                if card.isPeer {
                    if let path = chatCardPath(type, card) { Task { await peerApp.open(path) } }
                } else if let route = cardRoute(type, card) {
                    shell?.push(route)
                }
            },
            onBook: { card in
                if card.isPeer {
                    Task { await peerApp.open(chatVenueBookPath(card)) }
                // 发的人选了活动类型就直接订那个活动类型，否则打开门店页（那里列出每个能订的活动类型）。
                } else if let activityType = VenueActivityType.allCases.first(where: { $0.rawValue == card.subtype }) {
                    shell?.push(NearRoute.venueBook(venueId: card.targetId, activityType: activityType))
                } else {
                    shell?.push(NearRoute.venue(venueId: card.targetId, sheet: nil))
                }
            },
            onOpenProfile: { shell?.push(NearRoute.socialProfile(profileId: $0)) }
        )
    }

    /** 卡片打开的页面（Android `openCard`）。 */
    private func cardRoute(_ type: MessageType, _ card: ChatSharedCardContent) -> NearRoute? {
        switch type {
        case .eventShare: card.subtype.map { .activity(activityType: NearActivityKind.fromActivityType(NearActivityType.fromWire($0)), activityId: card.targetId) }
        case .venueShare: .venue(venueId: card.targetId, sheet: nil)
        case .buildingShare: .building(buildingId: card.targetId)
        case .postShare: .post(postId: card.targetId)
        case .forumShare: .forum(forumId: card.targetId)
        default: nil
        }
    }

    /** 时间分隔：今天只写时间，昨天「昨天 时间」，一周内星期 + 时间，今年月日 + 时间，更早带年份（Android `chatTimeLabel`）。 */
    private func chatTimeLabel(_ millis: Double) -> String {
        let date = Date(timeIntervalSince1970: millis / 1000)
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        let time = date.formatted(date: .omitted, time: .shortened)
        if days <= 0 { return time }
        if days == 1 { return localizedFormat("shell_chat_time_yesterday", time) }
        if days < 7 { return date.formatted(.dateTime.weekday(.wide).hour().minute()) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /** 长按的深色操作条（参照 long_press.jpg）。 */
    private func actionBar(_ message: ChatMessageRowUi) -> some View {
        HStack(spacing: 28) {
            ForEach(message.actions, id: \.self) { action in
                Button {
                    actionsFor = nil
                    perform(action, on: message)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: symbol(action)).font(.title3)
                        Text(label(action)).font(.caption)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.25))
        .presentationDetents([.height(110)])
        .presentationBackground(Color(white: 0.25))
    }

    private func perform(_ action: ChatMessageAction, on message: ChatMessageRowUi) {
        switch action {
        case .copy:
            UIPasteboard.general.string = message.text
            PulsoMessageCenter.shared.success("shell_chat_copied")
        case .forward: model.forwarding = message
        case .quote: model.quote(message)
        case .unsend: unsending = message
        }
    }

    private func symbol(_ action: ChatMessageAction) -> String {
        switch action {
        case .copy: "doc.on.doc"
        case .forward: "arrowshape.turn.up.right"
        case .quote: "quote.opening"
        case .unsend: "arrow.uturn.backward"
        }
    }

    private func label(_ action: ChatMessageAction) -> LocalizedStringKey {
        switch action {
        case .copy: "shell_chat_action_copy"
        case .forward: "shell_chat_action_forward"
        case .quote: "shell_chat_action_quote"
        case .unsend: "shell_chat_action_unsend"
        }
    }

    /** 撤回要按住确认（会影响聊天里的所有人）。 */
    private func unsendSheet(_ message: ChatMessageRowUi) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("shell_chat_unsend_confirm_title").font(.title3.bold())
            Text("shell_chat_unsend_confirm_text").foregroundStyle(.secondary)
            PulsoHoldButton("shell_chat_action_unsend") {
                Task {
                    await model.unsend(message)
                    unsending = nil
                }
            }
        }
        .padding(24)
        .presentationDetents([.height(240)])
    }

    /** 转发给哪个会话（Android `ChatForwardSheet`）。 */
    private var forwardSheet: some View {
        NavigationStack {
            List {
                let targets = model.allConversations
                if targets.isEmpty {
                    ContentUnavailableView("shell_chat_forward_empty", systemImage: "bubble.left.and.bubble.right")
                }
                ForEach(targets) { target in
                    Button { Task { await model.forward(to: target) } } label: { ConversationRowView(row: target) }
                        .buttonStyle(.plain)
                }
            }
            .navigationTitle("shell_chat_forward_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("shell_chat_cancel") { model.forwarding = nil } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/** 全屏弹层用的可识别地址。 */
private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/** 聊天里点开的位置（Android `ChatLocationViewScreen`）：地图停在那里，下面是名字、地址和「在地图 App 里打开」。 */
struct ChatLocationView: View {
    let latitude: Double
    let longitude: Double
    let label: String?
    let address: String?
    @Injected(\.preferenceService) private var preferenceService
    @State private var map = ResolvedMapPreference()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            NearMapView(map: map, initialCenter: (latitude, longitude), initialZoom: 16)
                .overlay { Image(systemName: "mappin.circle.fill").font(.largeTitle).foregroundStyle(.red) }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: label ?? address ?? String(localized: "shell_chat_plus_location")).font(.headline)
                if let address, address != label { Text(verbatim: address).font(.subheadline).foregroundStyle(.secondary) }
                Text("shell_chat_location_view_hint").font(.caption).foregroundStyle(.secondary)
                Button {
                    // 地图 App 导航过去（Android 打开 geo: 或 Google 地图路线）。
                    var components = URLComponents(string: "https://maps.apple.com/")!
                    components.queryItems = [URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)")]
                    if let url = components.url { openURL(url) }
                } label: {
                    Label("shell_chat_location_view_directions", systemImage: "arrow.triangle.turn.up.right.diamond").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pulso())
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .navigationTitle("shell_chat_location_view_title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for await preference in preferenceService.preference.values() { map = preference.map }
        }
    }
}

/** 聊天里选位置（Android `ChatLocationPickScreen`）：复用选点页，不写进附近搜索中心，选好作为草稿交给聊天室。 */
struct ChatLocationPickView: View {
    let conversationId: String
    @Injected(\.chatShareDraftStore) private var drafts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocationPickView(persistToExplore: false, confirmText: "shell_chat_location_confirm") { latitude, longitude, label in
            drafts.emit(.location(conversationId: conversationId, latitude: latitude, longitude: longitude, label: label, address: label))
            dismiss()
        }
    }
}
