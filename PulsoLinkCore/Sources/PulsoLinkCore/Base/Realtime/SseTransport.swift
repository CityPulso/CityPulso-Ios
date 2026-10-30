import Foundation
import LDSwiftEventSource

/**
 * Centrifugo SSE 兜底（Android `SseTransport`，只在后端没给 websocket 时用）：`GET {endpoint}?cf_connect={"token":…}`；
 * 令牌里写了本身份的频道，服务端直接订阅；推送帧是 `{"channel":…,"pub":{"data":{…}}}`。
 */
final class SseTransport: RealtimeTransport, @unchecked Sendable {
    private let params: RealtimeTransportParams
    private let listener: RealtimeTransportListener
    private var source: EventSource?

    init(params: RealtimeTransportParams, listener: RealtimeTransportListener) {
        self.params = params
        self.listener = listener
    }

    func connect() {
        guard var components = URLComponents(string: params.endpoint),
              let connect = try? JSONSerialization.data(withJSONObject: ["token": params.token]) else { return }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "cf_connect", value: String(decoding: connect, as: UTF8.self))]
        guard let url = components.url else { return }
        var config = EventSource.Config(handler: Handler(listener: listener), url: url)
        config.headers = ["Accept": "text/event-stream"]
        // 长连接：读超时放到一天（Android readTimeout 0）。
        config.idleTimeout = 60 * 60 * 24
        let source = EventSource(config: config)
        source.start()
        self.source = source
    }

    func disconnect() {
        source?.stop()
        source = nil
    }

    /** Centrifugo 单向 SSE 帧：只关心推送（连接确认等其余帧忽略）。 */
    private struct Frame: Decodable {
        struct Pub: Decodable {
            let data: WireJSON?
        }

        let pub: Pub?
    }

    private final class Handler: EventHandler, @unchecked Sendable {
        let listener: RealtimeTransportListener

        init(listener: RealtimeTransportListener) {
            self.listener = listener
        }

        func onOpened() {
            listener.onConnected()
            listener.onSubscribed()
        }

        func onClosed() {
            listener.onDisconnected()
        }

        func onMessage(eventType: String, messageEvent: MessageEvent) {
            guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(messageEvent.data.utf8)),
                  let payload = frame.pub?.data,
                  let bytes = try? JSONEncoder().encode(payload) else { return }
            listener.onPublication(bytes)
        }

        func onComment(comment: String) {}

        func onError(error: Error) {
            listener.onError(error)
        }
    }
}
