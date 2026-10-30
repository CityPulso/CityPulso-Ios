import PulsoLinkCore

/** 球友给地图标记的地点（Android `PlaceRequestService`）；每次写操作都让「我标记的地点」列表重拉。 */
struct PlaceRequestService: Sendable {
    let repository: PlaceRequestRepository
    let changes = EventBroadcast<Void>()

    @MainActor
    func pageMine(_ status: PlaceRequestStatus) -> PagedList<PlaceRequest, Int> {
        let repository = repository
        let changes = changes
        return .offset(invalidates: { changes.signals { _ in true } }) { offset, limit in
            try await repository.listMine(status: status, offset: offset, limit: limit)
        }
    }

    func get(_ requestId: String) async throws -> PlaceRequest {
        try await repository.get(requestId)
    }

    /** 标记新地点，或重新提交被拒的 [requestId]。 */
    @discardableResult
    func submit(_ requestId: String?, _ body: SubmitPlaceRequest) async throws -> PlaceRequest {
        let out = if let requestId { try await repository.resubmit(requestId, body) } else { try await repository.submit(body) }
        changes.emit(())
        return out
    }

    func cancel(_ requestId: String) async throws {
        try await repository.cancel(requestId)
        changes.emit(())
    }
}
