import Foundation
import PulsoLinkCore

/** Loop 羽毛球仓储（对应 Android `BadmintonRepository`，对齐 WEB `ApiBadmintonRepository`）：解包 `data`。 */
struct BadmintonRepository: Sendable {
    let publicAPI: BadmintonPublicAPI
    let protectedAPI: BadmintonProtectedAPI

    func listBadmintonEvents(_ body: ListBadmintonEventsRequest) async throws -> BadmintonEventListResponse {
        try await publicAPI.listBadmintonEvents(body).dataOrThrow("ListBadmintonEvents")
    }

    func listMyBadmintonRegistrations(_ body: ListMyBadmintonRegistrationsRequest = ListMyBadmintonRegistrationsRequest()) async throws -> BadmintonMyRegistrationsResponse {
        try await protectedAPI.listMyBadmintonRegistrations(body).dataOrThrow("ListMyBadmintonRegistrations")
    }

    func listBadmintonProfileRegistrations(_ body: ListBadmintonProfileRegistrationsRequest) async throws -> BadmintonProfileRegistrationsResponse {
        try await publicAPI.listBadmintonProfileRegistrations(body).dataOrThrow("ListBadmintonProfileRegistrations")
    }

    func createBadmintonEvent(_ body: CreateBadmintonEventRequest) async throws -> CreateBadmintonEventResponse {
        try await protectedAPI.createBadmintonEvent(body).dataOrThrow("CreateBadmintonEvent")
    }

    func getBadmintonEventFullInformation(eventId: String) async throws -> BadmintonFullInformation {
        try await publicAPI.getBadmintonEventFullInformation(eventId: eventId).dataOrThrow("GetBadmintonEventFullInformation")
    }

    func incrementBadmintonEventView(eventId: String) async throws -> IncrementBadmintonEventViewResponse {
        try await publicAPI.incrementBadmintonEventView(eventId: eventId).dataOrThrow("IncrementBadmintonEventView")
    }

    func endBadmintonEvent(eventId: String, _ body: EndBadmintonEventRequest = EndBadmintonEventRequest()) async throws {
        try await protectedAPI.endBadmintonEvent(eventId: eventId, body)
    }

    func patchBadmintonEventBasic(eventId: String, _ body: PatchBadmintonEventBasicRequest) async throws {
        try await protectedAPI.patchBadmintonEventBasic(eventId: eventId, body)
    }

    func patchBadmintonEventRestricted(eventId: String, _ body: PatchBadmintonEventRestrictedRequest) async throws {
        try await protectedAPI.patchBadmintonEventRestricted(eventId: eventId, body)
    }

    func patchBadmintonEventAdvanced(eventId: String, _ body: PatchBadmintonEventAdvancedRequest) async throws {
        try await protectedAPI.patchBadmintonEventAdvanced(eventId: eventId, body)
    }

    func replaceBadmintonEventImages(eventId: String, _ body: ReplaceBadmintonEventImagesRequest) async throws {
        try await protectedAPI.replaceBadmintonEventImages(eventId: eventId, body)
    }

    func listBadmintonRegistrations(eventId: String, offset: Int? = nil, limit: Int? = nil, all: Bool? = nil, includeExited: Bool? = nil) async throws -> BadmintonRegistrationsPage {
        try await publicAPI.listBadmintonRegistrations(eventId: eventId, offset: offset, limit: limit, all: all, includeExited: includeExited)
            .dataOrThrow("ListBadmintonRegistrations")
    }

    func joinBadmintonEvent(eventId: String, _ body: JoinBadmintonEventRequest = JoinBadmintonEventRequest()) async throws -> JoinBadmintonEventResponse {
        try await protectedAPI.joinBadmintonEvent(eventId: eventId, body).dataOrThrow("JoinBadmintonEvent")
    }

    func getMyRegistrationPayment(eventId: String) async throws -> PaymentHoldSession {
        try await protectedAPI.getMyRegistrationPayment(eventId: eventId).dataOrThrow("GetMyRegistrationPayment")
    }

    func payMyRegistrationPayment(eventId: String, _ body: PayPaymentRequest) async throws -> PaymentAttempt {
        try await protectedAPI.payMyRegistrationPayment(eventId: eventId, body).dataOrThrow("PayMyRegistrationPayment")
    }

    func exitBadmintonEvent(eventId: String, _ body: ExitBadmintonEventRequest = ExitBadmintonEventRequest()) async throws -> BadmintonRegistration {
        try await protectedAPI.exitBadmintonEvent(eventId: eventId, body).dataOrThrow("ExitBadmintonEvent")
    }

    func updateMyRegistrationNote(eventId: String, _ body: BadmintonUpdatePlayerNoteRequest) async throws -> BadmintonRegistration {
        try await protectedAPI.updateMyRegistrationNote(eventId: eventId, body).dataOrThrow("UpdateMyRegistrationNote")
    }

    func getOrCreatePaymentChecklist(eventId: String) async throws -> BadmintonPaymentChecklistResponse {
        try await protectedAPI.getOrCreatePaymentChecklist(eventId: eventId).dataOrThrow("GetOrCreatePaymentChecklist")
    }

    func patchPaymentChecklistRemarks(eventId: String, remarks: String?) async throws -> BadmintonPaymentChecklistResponse {
        try await protectedAPI.patchPaymentChecklistRemarks(eventId: eventId, BadmintonPatchPaymentChecklistRemarksRequest(remarks: remarks))
            .dataOrThrow("PatchPaymentChecklistRemarks")
    }

    func settleAllPaymentChecklist(eventId: String) async throws -> BadmintonPaymentChecklistResponse {
        try await protectedAPI.settleAllPaymentChecklist(eventId: eventId).dataOrThrow("SettleAllPaymentChecklist")
    }

    func markPaymentChecklistItemPaid(itemId: String) async throws {
        try await protectedAPI.markPaymentChecklistItemPaid(itemId: itemId)
    }

    func markPaymentChecklistItemUnpaid(itemId: String) async throws {
        try await protectedAPI.markPaymentChecklistItemUnpaid(itemId: itemId)
    }

    func remindPaymentChecklistItems(eventId: String, itemIds: [String]) async throws {
        try await protectedAPI.remindPaymentChecklistItems(eventId: eventId, BadmintonRemindPaymentChecklistItemsRequest(itemIds: itemIds))
    }

    func listHostedPaymentChecklists(_ body: BadmintonListHostedPaymentChecklistsRequest = BadmintonListHostedPaymentChecklistsRequest()) async throws -> BadmintonHostedPaymentChecklistsPage {
        try await protectedAPI.listHostedPaymentChecklists(body).dataOrThrow("ListHostedPaymentChecklists")
    }

    func listMyPaymentChecklistItems(_ body: BadmintonListMyPaymentChecklistItemsRequest = BadmintonListMyPaymentChecklistItemsRequest()) async throws -> BadmintonMyPaymentChecklistItemsPage {
        try await protectedAPI.listMyPaymentChecklistItems(body).dataOrThrow("ListMyPaymentChecklistItems")
    }
}
