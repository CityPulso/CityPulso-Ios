import Foundation

/** 发起一场活动（每种活动的 Service 遵守；请求体各活动不同，Android `CreateRequests.kt`）。返回新活动 id。 */
protocol ActivityTypeCreateService: Sendable {
    func createActivity(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String
}
