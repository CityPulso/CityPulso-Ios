import Foundation

/** 发起一场活动（每个运动的 Service 遵守；请求体各运动不同，Android `CreateRequests.kt`）。返回新活动 id。 */
protocol SportCreateService: Sendable {
    func createEvent(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String
}
