import PulsoLinkCore

/**
 * 跨运动的页面（日历、资料、场馆建筑…）读某一运动活动的统一入口。Android 在这些页面里对 11 个 Service 写
 * `when (sport)`；iOS 让每个 Service 遵守这个协议（`Services/<Sport>Service+Sport.swift`），按 [LoopSport] 取。
 */
/** 我的报名查询（对应各运动的 `My<Sport>RegistrationsKey`，账号 / 身份由调用方给）。 */
struct SportRegistrationsQuery: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var limit: Int
    var includeEnded = true
    /** 不含我主持的。 */
    var excludeHosted = false
}

protocol LoopSportService: Sendable {
    var sport: LoopSport { get }

    /** [hostedProfileId] 主持的活动（含已结束），最多 [limit] 条。 */
    func hostedEvents(accountId: String, profileId: String, hostedProfileId: String, limit: Int) -> AsyncStream<QueryResponse<[any SportEventItem]>>

    func freshHostedEvents(accountId: String, profileId: String, hostedProfileId: String, limit: Int) async throws

    func myRegistrations(_ query: SportRegistrationsQuery) -> AsyncStream<QueryResponse<[any SportRegistrationItem]>>

    func freshMyRegistrations(_ query: SportRegistrationsQuery) async throws
}

extension AsyncStream {
    /** 把查询结果里的值换个形状，loading / error 原样传。 */
    func mapResponses<T: Sendable, R: Sendable>(_ transform: @escaping @Sendable (T) -> R) -> AsyncStream<QueryResponse<R>> where Element == QueryResponse<T> {
        let source = self
        return AsyncStream<QueryResponse<R>> { continuation in
            let task = Task {
                for await response in source {
                    switch response {
                    case .loading: continuation.yield(.loading)
                    case let .data(value): continuation.yield(.data(transform(value)))
                    case let .error(error): continuation.yield(.error(error))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
