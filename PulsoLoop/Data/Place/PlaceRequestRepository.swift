import PulsoLinkCore

/** 球友标记的地点（Android `PlaceRequestRepository`）：按状态列出、读一条、标记、重新提交被拒的、撤回。 */
struct PlaceRequestRepository: Sendable {
    let api: PlaceRequestAPI

    func listMine(status: PlaceRequestStatus, offset: Int, limit: Int) async throws -> ListWithTotal<PlaceRequest> {
        try await api.listMine(status: status.rawValue, offset: offset, limit: limit).dataOrThrow("ListMyPlaceRequests")
    }

    func get(_ requestId: String) async throws -> PlaceRequest {
        try await api.get(requestId: requestId).dataOrThrow("GetPlaceRequest")
    }

    func submit(_ body: SubmitPlaceRequest) async throws -> PlaceRequest {
        try await api.submit(body).dataOrThrow("SubmitPlaceRequest")
    }

    func resubmit(_ requestId: String, _ body: SubmitPlaceRequest) async throws -> PlaceRequest {
        try await api.resubmit(requestId: requestId, body).dataOrThrow("ResubmitPlaceRequest")
    }

    func cancel(_ requestId: String) async throws {
        try await api.cancel(requestId: requestId)
    }
}
