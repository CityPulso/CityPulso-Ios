#if canImport(SwiftCentrifuge)
import Foundation
import SwiftCentrifuge

/**
 * Centrifugo WebSocket 传输（Android `CentrifugeWebSocketTransport`）：令牌过期由 tokenGetter 重取；
 * 连接令牌里写了 `profile:{scope}:{id}`，服务端直接订阅，推送从连接上的 onPublication 到达，只转发本身份频道的。
 */
final class CentrifugeWebSocketTransport: RealtimeTransport, CentrifugeClientDelegate, @unchecked Sendable {
    private let params: RealtimeTransportParams
    private let listener: RealtimeTransportListener
    private var client: CentrifugeClient?

    init(params: RealtimeTransportParams, listener: RealtimeTransportListener) {
        self.params = params
        self.listener = listener
    }

    func connect() {
        let getToken = params.getToken
        let config = CentrifugeClientConfig(token: params.token, tokenGetter: { _, completion in
            // centrifuge-swift 只调一次回调，回调本身不是 Sendable。
            let reply = TokenReply(completion)
            Task {
                do {
                    reply.send(.success(try await getToken()))
                } catch {
                    reply.send(.failure(error))
                }
            }
        })
        let client = CentrifugeClient(endpoint: params.endpoint, config: config, delegate: self)
        client.connect()
        self.client = client
    }

    func disconnect() {
        client?.disconnect()
        client = nil
    }

    func onConnected(_ client: CentrifugeClient, _ event: CentrifugeConnectedEvent) {
        listener.onConnected()
    }

    func onDisconnected(_ client: CentrifugeClient, _ event: CentrifugeDisconnectedEvent) {
        listener.onDisconnected()
    }

    func onError(_ client: CentrifugeClient, _ event: CentrifugeErrorEvent) {
        listener.onError(event.error)
    }

    func onSubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribedEvent) {
        guard event.channel == params.channel else { return }
        listener.onSubscribed()
    }

    func onPublication(_ client: CentrifugeClient, _ event: CentrifugeServerPublicationEvent) {
        guard event.channel == params.channel else { return }
        listener.onPublication(event.data)
    }
}
/** 把令牌回调带进 Task（库保证只调一次）。 */
private final class TokenReply: @unchecked Sendable {
    private let completion: (Result<String, Error>) -> Void

    init(_ completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
    }

    func send(_ result: Result<String, Error>) {
        completion(result)
    }
}
#endif
