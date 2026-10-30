import Foundation

/** 推送信封 `{ id, type, data }`（Android `RealtimePublication`，WEB `Realtime.WireEnvelope`）；`data` 由宿主按 `type` 解析。 */
public struct RealtimePublication: Decodable, Sendable {
    public let id: String
    public let type: String
    public let data: [String: WireJSON]

    /** 结构不对时 nil（WEB `parsePublication`）。 */
    static func parse(_ raw: Data) -> RealtimePublication? {
        try? JSONDecoder().decode(RealtimePublication.self, from: raw)
    }
}

/** 实时连接状态（Android `RealtimeEvent`）。 */
public enum RealtimeEvent: Sendable, Equatable {
    case connected
    case disconnected
}

public typealias RealtimeEventBus = EventBroadcast<RealtimeEvent>

/**
 * 推送分发（Android `RealtimePublicationDispatcher`，WEB `RealtimeProvider.onPublication`）：未知类型丢掉；
 * 每种推送先在 core 里让对应缓存失效（通知 / 会话 / 好友请求）并重查红点，再交给宿主登记的产品处理（导航等）。
 */
public final class RealtimePublicationDispatcher: @unchecked Sendable {
    private let communicationBus: CommunicationEventBus
    private let socialBus: SocialEventBus
    private let inbox: InboxIndicatorStore
    private let lock = NSLock()
    private var handler: (@Sendable (RealtimePublicationType, RealtimePublication) -> Void)?

    public init(communicationBus: CommunicationEventBus, socialBus: SocialEventBus, inbox: InboxIndicatorStore) {
        self.communicationBus = communicationBus
        self.socialBus = socialBus
        self.inbox = inbox
    }

    /** 宿主 App 登记产品级处理。 */
    public func setHandler(_ handler: @escaping @Sendable (RealtimePublicationType, RealtimePublication) -> Void) {
        lock.withLock { self.handler = handler }
    }

    func dispatch(_ publication: RealtimePublication) {
        guard let type = RealtimePublicationType(rawValue: publication.type) else { return }
        // 缓存失效是 core 的事，产品 App 不登记处理也能保持同步。
        let inbox = inbox
        switch type {
        case .notificationCreated:
            communicationBus.emit(.invalidateNotifications)
        case .communicationInboxUpdated, .communicationConversationCreated:
            communicationBus.emit(.invalidateConversations)
            Task {
                try? await inbox.recheckDirectChatUnread()
                try? await inbox.recheckGroupChatUnread()
            }
        case .socialFriendRequestReceived:
            socialBus.emit(.invalidateFriendRequests(.incoming))
            Task { try? await inbox.recheckFriendRequestIncoming() }
        }
        lock.withLock { handler }?(type, publication)
    }
}

/**
 * 实时连接的生命周期（Android `RealtimeConnectionManager`，WEB `useCentrifugoConnection`）：
 * 只在「登录有效 + 有 accessToken + 已选身份」时连；会话变了就重建。websocket 优先，其次 sse / http_stream。
 * 频道 `profile:{scope}:{profileId}`；推送解析后交给 [RealtimePublicationDispatcher]。
 */
public final class RealtimeConnectionManager: @unchecked Sendable {
    private struct ConnectionKey: Equatable {
        let profileId: String
        let profileScope: String
    }

    private let communication: CommunicationRepository
    private let sessionStore: AuthSessionStore
    private let dispatcher: RealtimePublicationDispatcher
    private let realtimeBus: RealtimeEventBus
    private let communicationBus: CommunicationEventBus
    private let socialBus: SocialEventBus
    private let inbox: InboxIndicatorStore
    private let lock = NSLock()
    private var transport: (any RealtimeTransport)?
    private var started = false

    public init(
        communication: CommunicationRepository, sessionStore: AuthSessionStore, dispatcher: RealtimePublicationDispatcher,
        realtimeBus: RealtimeEventBus, communicationBus: CommunicationEventBus, socialBus: SocialEventBus, inbox: InboxIndicatorStore
    ) {
        self.communication = communication
        self.sessionStore = sessionStore
        self.dispatcher = dispatcher
        self.realtimeBus = realtimeBus
        self.communicationBus = communicationBus
        self.socialBus = socialBus
        self.inbox = inbox
    }

    /** channel 命名与 WEB `profileChannel` 一致。 */
    public static func profileChannel(_ profileId: String, _ profileScope: String) -> String {
        "profile:\(profileScope):\(profileId)"
    }

    /** App 启动时调一次。 */
    public func start() {
        guard lock.withLock({ () -> Bool in
            defer { started = true }
            return !started
        }) else { return }
        let sessions = sessionStore.state.values()
        Task {
            var current: ConnectionKey?
            var first = true
            for await session in sessions {
                let key: ConnectionKey? = session.isAuthValid && !(session.accessToken ?? "").isEmpty && session.hasSelectedProfile
                    ? ConnectionKey(profileId: session.currentProfileId, profileScope: session.currentProfileKind.rawValue)
                    : nil
                guard first || key != current else { continue }
                first = false
                current = key
                teardown()
                if let key { await connect(key) }
            }
        }
    }

    private func connect(_ key: ConnectionKey) async {
        do {
            let token = try await communication.getRealtimeToken()
            let selected = token.transports.first { $0.transport == "websocket" }
                ?? token.transports.first { $0.transport == "sse" || $0.transport == "http_stream" }
                ?? token.transports.first
            guard let selected, !selected.endpoint.isEmpty else { return }
            let communication = communication
            let params = RealtimeTransportParams(
                endpoint: selected.endpoint,
                token: token.token,
                channel: Self.profileChannel(key.profileId, key.profileScope),
                getToken: { try await communication.getRealtimeToken().token }
            )
            let realtimeBus = realtimeBus
            let communicationBus = communicationBus
            let socialBus = socialBus
            let inbox = inbox
            let dispatcher = dispatcher
            let listener = RealtimeTransportListener(
                onConnected: { realtimeBus.emit(.connected) },
                onDisconnected: { realtimeBus.emit(.disconnected) },
                onSubscribed: {
                    // （重新）订阅上了：离线期间的推送都漏了，离线优先的列表和红点全部重拉。
                    communicationBus.emit(.invalidateNotifications)
                    communicationBus.emit(.invalidateConversations)
                    socialBus.emit(.invalidateFriendRequests(nil))
                    Task { try? await inbox.sync() }
                },
                onPublication: { data in
                    if let publication = RealtimePublication.parse(data) { dispatcher.dispatch(publication) }
                },
                onError: { _ in }
            )
            let next = makeTransport(selected.transport, params, listener)
            lock.withLock { transport = next }
            next.connect()
        } catch {
            // 拿不到令牌：下次会话变化再连。
        }
    }

    private func makeTransport(_ kind: String, _ params: RealtimeTransportParams, _ listener: RealtimeTransportListener) -> any RealtimeTransport {
        #if canImport(SwiftCentrifuge)
        if kind == "websocket" { return CentrifugeWebSocketTransport(params: params, listener: listener) }
        #endif
        return SseTransport(params: params, listener: listener)
    }

    private func teardown() {
        let current = lock.withLock { () -> (any RealtimeTransport)? in
            defer { transport = nil }
            return transport
        }
        current?.disconnect()
    }
}
