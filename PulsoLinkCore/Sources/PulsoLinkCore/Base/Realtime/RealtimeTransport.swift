import Foundation

/** 实时传输（Android `RealtimeTransport`）：WebSocket（centrifuge-swift）优先，SSE（swift-eventsource）兜底。 */
protocol RealtimeTransport: AnyObject {
    func connect()
    func disconnect()
}

/** 传输回调：连接状态 + 原始推送字节（Android `RealtimeTransportListener`）。 */
struct RealtimeTransportListener: Sendable {
    var onConnected: @Sendable () -> Void
    var onDisconnected: @Sendable () -> Void
    /** 频道订阅成功（离线期间漏掉的推送要全部重拉）。 */
    var onSubscribed: @Sendable () -> Void
    var onPublication: @Sendable (Data) -> Void
    var onError: @Sendable (any Error) -> Void
}

/** 连接参数；令牌过期时用 [getToken] 重取。 */
struct RealtimeTransportParams: Sendable {
    let endpoint: String
    let token: String
    let channel: String
    let getToken: @Sendable () async throws -> String
}
