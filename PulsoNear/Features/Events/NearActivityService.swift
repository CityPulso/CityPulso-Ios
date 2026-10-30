import PulsoLinkCore

/**
 * 跨活动类型的页面（日历、资料、场馆建筑…）读某一活动类型活动的统一入口。Android 在这些页面里对 11 个 Service 写
 * `when (activityType)`；iOS 让每个 Service 遵守这个协议（`Services/<ActivityType>Service+ActivityType.swift`），按 [NearActivityKind] 取。
 */
/** 我的报名查询（对应各活动类型的 `My<ActivityType>RegistrationsKey`，账号 / 身份由调用方给）。 */
struct ActivityTypeRegistrationsQuery: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var limit: Int
    var includeEnded = true
    /** 不含我主持的。 */
    var excludeHosted = false
}

protocol NearActivityService: ActivityDetailService, ActivityTypeChecklistService, ActivityTypeCreateService {
    var activityType: NearActivityKind { get }

    /** [hostedProfileId] 主持的活动（含已结束），最多 [limit] 条。 */
    func hostedActivities(accountId: String, profileId: String, hostedProfileId: String, limit: Int) -> AsyncStream<QueryResponse<[any ActivityItem]>>

    func freshHostedActivities(accountId: String, profileId: String, hostedProfileId: String, limit: Int) async throws

    func myRegistrations(_ query: ActivityTypeRegistrationsQuery) -> AsyncStream<QueryResponse<[any ActivityTypeRegistrationItem]>>

    /** 别人主页「参加的」：[profileId] 报名过的活动（含已结束），最多 [limit] 条。 */
    func profileRegistrations(profileId: String, limit: Int) -> AsyncStream<QueryResponse<[any ActivityItem]>>

    func freshMyRegistrations(_ query: ActivityTypeRegistrationsQuery) async throws

    /** 在 [buildingId] 这栋建筑办的活动；[endedOnly] 时只要已结束的（门店详情的「活动」分段）。 */
    func buildingActivities(accountId: String, profileId: String, buildingId: String, endedOnly: Bool) -> AsyncStream<QueryResponse<[any ActivityItem]>>

    /** 账单「我主持的」：我主持的活动的收款清单，分页。 */
    @MainActor
    func pageHostedChecklists(isAllSettled: Bool) -> PagedList<HostedChecklistRowUi, Int>

    /** 账单「我的付款」：我自己的收款行，分页。 */
    @MainActor
    func pageMyPaymentItems(paid: Bool) -> PagedList<MyChecklistItemRowUi, Int>
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
