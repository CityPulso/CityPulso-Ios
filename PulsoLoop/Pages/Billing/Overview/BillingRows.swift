import Foundation

/** 账单「我主持的」一行（Android `HostedChecklistRowUi`）。 */
struct HostedChecklistRowUi: Codable, Sendable, Hashable, Identifiable {
    let checklistId: String
    let eventId: String
    let title: String
    let venueName: String?
    let startsAt: String
    let isAllSettled: Bool

    var id: String { checklistId }
}

/** 账单「我的付款」一行（Android `MyChecklistItemRowUi`）。 */
struct MyChecklistItemRowUi: Codable, Sendable, Hashable, Identifiable {
    let itemId: String
    let eventId: String
    let title: String
    let venueName: String?
    let startsAt: String
    let paid: Bool
    let priceAmount: Double?
    let currency: String

    var id: String { itemId }
}
