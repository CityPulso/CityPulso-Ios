import Foundation
import PulsoLinkCore

/** Near 桌游仓储（对应 Android `BoardGameRepository`，对齐 WEB `ApiBoardGameRepository`）：解包 `data`。 */
struct BoardGameRepository: Sendable {
    let publicAPI: BoardGamePublicAPI
    let protectedAPI: BoardGameProtectedAPI

    func listBoardGameActivities(_ body: ListBoardGameActivitiesRequest) async throws -> BoardGameActivityListResponse {
        try await publicAPI.listBoardGameActivities(body).dataOrThrow("ListBoardGameActivities")
    }

    func listMyBoardGameRegistrations(_ body: ListMyBoardGameRegistrationsRequest = ListMyBoardGameRegistrationsRequest()) async throws -> BoardGameMyRegistrationsResponse {
        try await protectedAPI.listMyBoardGameRegistrations(body).dataOrThrow("ListMyBoardGameRegistrations")
    }

    func listBoardGameProfileRegistrations(_ body: ListBoardGameProfileRegistrationsRequest) async throws -> BoardGameProfileRegistrationsResponse {
        try await publicAPI.listBoardGameProfileRegistrations(body).dataOrThrow("ListBoardGameProfileRegistrations")
    }

    func createBoardGameActivity(_ body: CreateBoardGameActivityRequest) async throws -> CreateBoardGameActivityResponse {
        try await protectedAPI.createBoardGameActivity(body).dataOrThrow("CreateBoardGameActivity")
    }

    func getBoardGameActivityFullInformation(activityId: String) async throws -> BoardGameFullInformation {
        try await publicAPI.getBoardGameActivityFullInformation(activityId: activityId).dataOrThrow("GetBoardGameActivityFullInformation")
    }

    func incrementBoardGameActivityView(activityId: String) async throws -> IncrementBoardGameActivityViewResponse {
        try await publicAPI.incrementBoardGameActivityView(activityId: activityId).dataOrThrow("IncrementBoardGameActivityView")
    }

    func endBoardGameActivity(activityId: String, _ body: EndBoardGameActivityRequest = EndBoardGameActivityRequest()) async throws {
        try await protectedAPI.endBoardGameActivity(activityId: activityId, body)
    }

    func patchBoardGameActivityBasic(activityId: String, _ body: PatchBoardGameActivityBasicRequest) async throws {
        try await protectedAPI.patchBoardGameActivityBasic(activityId: activityId, body)
    }

    func patchBoardGameActivityRestricted(activityId: String, _ body: PatchBoardGameActivityRestrictedRequest) async throws {
        try await protectedAPI.patchBoardGameActivityRestricted(activityId: activityId, body)
    }

    func patchBoardGameActivityAdvanced(activityId: String, _ body: PatchBoardGameActivityAdvancedRequest) async throws {
        try await protectedAPI.patchBoardGameActivityAdvanced(activityId: activityId, body)
    }

    func replaceBoardGameActivityImages(activityId: String, _ body: ReplaceBoardGameActivityImagesRequest) async throws {
        try await protectedAPI.replaceBoardGameActivityImages(activityId: activityId, body)
    }

    func listBoardGameRegistrations(activityId: String, offset: Int? = nil, limit: Int? = nil, all: Bool? = nil, includeExited: Bool? = nil) async throws -> BoardGameRegistrationsPage {
        try await publicAPI.listBoardGameRegistrations(activityId: activityId, offset: offset, limit: limit, all: all, includeExited: includeExited)
            .dataOrThrow("ListBoardGameRegistrations")
    }

    func joinBoardGameActivity(activityId: String, _ body: JoinBoardGameActivityRequest = JoinBoardGameActivityRequest()) async throws -> JoinBoardGameActivityResponse {
        try await protectedAPI.joinBoardGameActivity(activityId: activityId, body).dataOrThrow("JoinBoardGameActivity")
    }

    func getMyRegistrationPayment(activityId: String) async throws -> PaymentHoldActivity {
        try await protectedAPI.getMyRegistrationPayment(activityId: activityId).dataOrThrow("GetMyRegistrationPayment")
    }

    func payMyRegistrationPayment(activityId: String, _ body: PayPaymentRequest) async throws -> PaymentAttempt {
        try await protectedAPI.payMyRegistrationPayment(activityId: activityId, body).dataOrThrow("PayMyRegistrationPayment")
    }

    func exitBoardGameActivity(activityId: String, _ body: ExitBoardGameActivityRequest = ExitBoardGameActivityRequest()) async throws -> BoardGameRegistration {
        try await protectedAPI.exitBoardGameActivity(activityId: activityId, body).dataOrThrow("ExitBoardGameActivity")
    }

    func updateMyRegistrationNote(activityId: String, _ body: BoardGameUpdatePlayerNoteRequest) async throws -> BoardGameRegistration {
        try await protectedAPI.updateMyRegistrationNote(activityId: activityId, body).dataOrThrow("UpdateMyRegistrationNote")
    }

    func getOrCreatePaymentChecklist(activityId: String) async throws -> BoardGamePaymentChecklistResponse {
        try await protectedAPI.getOrCreatePaymentChecklist(activityId: activityId).dataOrThrow("GetOrCreatePaymentChecklist")
    }

    func patchPaymentChecklistRemarks(activityId: String, remarks: String?) async throws -> BoardGamePaymentChecklistResponse {
        try await protectedAPI.patchPaymentChecklistRemarks(activityId: activityId, BoardGamePatchPaymentChecklistRemarksRequest(remarks: remarks))
            .dataOrThrow("PatchPaymentChecklistRemarks")
    }

    func settleAllPaymentChecklist(activityId: String) async throws -> BoardGamePaymentChecklistResponse {
        try await protectedAPI.settleAllPaymentChecklist(activityId: activityId).dataOrThrow("SettleAllPaymentChecklist")
    }

    func markPaymentChecklistItemPaid(itemId: String) async throws {
        try await protectedAPI.markPaymentChecklistItemPaid(itemId: itemId)
    }

    func markPaymentChecklistItemUnpaid(itemId: String) async throws {
        try await protectedAPI.markPaymentChecklistItemUnpaid(itemId: itemId)
    }

    func remindPaymentChecklistItems(activityId: String, itemIds: [String]) async throws {
        try await protectedAPI.remindPaymentChecklistItems(activityId: activityId, BoardGameRemindPaymentChecklistItemsRequest(itemIds: itemIds))
    }

    func listHostedPaymentChecklists(_ body: BoardGameListHostedPaymentChecklistsRequest = BoardGameListHostedPaymentChecklistsRequest()) async throws -> BoardGameHostedPaymentChecklistsPage {
        try await protectedAPI.listHostedPaymentChecklists(body).dataOrThrow("ListHostedPaymentChecklists")
    }

    func listMyPaymentChecklistItems(_ body: BoardGameListMyPaymentChecklistItemsRequest = BoardGameListMyPaymentChecklistItemsRequest()) async throws -> BoardGameMyPaymentChecklistItemsPage {
        try await protectedAPI.listMyPaymentChecklistItems(body).dataOrThrow("ListMyPaymentChecklistItems")
    }
}
