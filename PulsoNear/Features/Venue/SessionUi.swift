import Foundation
import PulsoLinkCore

/*
 * 场次类门店（密室逃脱的主题、剧本杀的剧本；Android `VenueBookingTemplate.SESSION`）不分活动类型的形状：
 * 每种门店保留自己的 DTO，预约页只画这些（Android `SessionBookPage` 里的 `SessionBookRules` / `SessionRowUi`）。
 */

/** 门店这种场次入口的规则（`<ActivityType>Entry`）。 */
struct SessionEntryUi: Hashable, Sendable {
    let status: PublicationStatus
    let bookingWindowDays: Int
    let bookingLeadMinutes: Int
    let slotMinutes: Int
    let bufferMinutes: Int
    let refundPolicy: SpaceRefundPolicy
    let refundPolicyNote: String?
    let refundTiers: [SpaceRefundTierUi]
    /** 主题 / 剧本数。 */
    let optionCount: Int
    let minSessionPriceAmount: Double?
    let timezone: String
    let currency: String
    let venueStatus: PublicationStatus
}

/** 一个主题（密室）或一个剧本（剧本杀）：时长、人数、难度、按场的价格和每多一人的加价。 */
struct SessionOptionUi: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /** 剧本杀的题材（欢乐 / 硬核…）；密室是主题所在的房间名。 */
    let subtitle: String?
    let description: String?
    let sortOrder: Int
    let durationMinutes: Int
    let playersMin: Int
    let playersMax: Int
    let difficulty: SessionDifficulty
    let priceAmount: Double
    let extraPlayerAmount: Double?
    let isActive: Bool
    let images: [StoredVenueImage]
}

struct SessionSlotUi: Hashable, Sendable {
    let startsAt: String
    let endsAt: String
    let available: Bool
    let priceCents: Int
}

/** 某天一个主题 / 剧本能开的场次。 */
struct SessionRowUi: Identifiable, Hashable, Sendable {
    let optionId: String
    let name: String
    let sortOrder: Int
    let durationMinutes: Int
    let slots: [SessionSlotUi]

    var id: String { optionId }
}

/** 某天的场次表（`<ActivityType>DayGrid`）。 */
struct SessionDayUi: Hashable, Sendable {
    let date: String
    let bookable: Bool
    let rows: [SessionRowUi]
}

/** 下单：哪个主题 / 剧本、几点开始、几个人。 */
struct SessionCheckoutInput: Sendable {
    let paymentMethod: SpaceBookingPaymentMethod
    let optionId: String
    let startsAt: String
    let partySize: Int
    let contactName: String?
    let contactPhone: String?
    let note: String?
}

/** 按场次订的门店（密室、剧本杀）。 */
protocol SessionVenueService: VenueBookingService {
    func entry(venueId: String) -> AsyncStream<QueryResponse<SessionEntryUi>>
    func options(venueId: String) -> AsyncStream<QueryResponse<[SessionOptionUi]>>
    func availability(venueId: String, date: String) -> AsyncStream<QueryResponse<SessionDayUi>>
    func checkout(venueId: String, _ input: SessionCheckoutInput, idempotencyKey: String) async throws -> SpaceCheckoutResultUi
}

/** 选好的一场（Android `VenueSessionPick`）：主题 / 剧本、开始时间和人数。 */
struct VenueSessionPick: Hashable, Sendable, Codable {
    let optionId: String
    let startsAt: String
    let partySize: Int
}

/** [partySize] 个人一场的价格：底价加上超出最少人数的每人加价（WEB `escapeRoomSessionPriceCents`）。 */
func sessionPriceCents(_ basePriceCents: Int, extraPlayerAmount: Double?, playersMin: Int, partySize: Int) -> Int {
    let extraCents = extraPlayerAmount.map { Int(($0 * 100).rounded()) } ?? 0
    return basePriceCents + max(0, partySize - playersMin) * extraCents
}
