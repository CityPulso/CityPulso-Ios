import Foundation
import PulsoLinkCore
import SwiftUI

/*
 * 运动无关的订场形状（Android `CourtBoardUi` / `CourtBookUi` 和各运动的 `*AvailabilitySelection`）：每个运动保留自己的
 * DTO，`Services/<Sport>VenueService` 把它们换成这里的形状，订场 / 确认 / 我的订场页面只写一份。
 */

/** 球馆入口的退款政策（三种运动的 `<Sport>RefundPolicyType` 取值一样）。 */
enum CourtRefundPolicy: String, Hashable, Sendable {
    case nonRefundable = "non_refundable"
    case fullRefundMinusProviderFee = "full_refund_minus_provider_fee"
    case tiered

    init(wire: String) {
        self = CourtRefundPolicy(rawValue: wire) ?? .nonRefundable
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .nonRefundable: "venue_refund_types_non_refundable_title"
        case .fullRefundMinusProviderFee: "venue_refund_types_full_refund_minus_provider_fee_title"
        case .tiered: "venue_refund_types_tiered_title"
        }
    }

    var bodyKey: LocalizedStringKey {
        switch self {
        case .nonRefundable: "venue_refund_types_non_refundable_body"
        case .fullRefundMinusProviderFee: "venue_refund_types_full_refund_minus_provider_fee_body"
        case .tiered: "venue_refund_types_tiered_body"
        }
    }

    var summaryKey: LocalizedStringKey {
        switch self {
        case .nonRefundable: "venue_refund_summary_types_non_refundable"
        case .fullRefundMinusProviderFee: "venue_refund_summary_types_full_refund_minus_provider_fee"
        case .tiered: "venue_refund_summary_types_tiered"
        }
    }
}

struct CourtRefundTierUi: Hashable, Sendable {
    let hoursBeforeStart: Int
    let refundPercent: Int
}

/** 一个运动入口：预订规则、退款政策和摘要（`<Sport>Entry`）。 */
struct CourtEntryUi: Hashable, Sendable {
    let status: PublicationStatus
    let bookingWindowDays: Int
    let bookingLeadMinutes: Int
    let slotMinutes: Int
    let minBookingMinutes: Int
    let maxBookingMinutes: Int
    let refundPolicy: CourtRefundPolicy
    let refundPolicyNote: String?
    let refundTiers: [CourtRefundTierUi]
    let courtCount: Int
    let minHourlyPriceAmount: Double?
    let timezone: String
    let currency: String
    let venueStatus: PublicationStatus
}

/** 一块场地（`<Sport>Court`）；[hours] 周一在前，缺的那天休息。 */
struct CourtUi: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int
    let surface: CourtSurface
    let description: String?
    let isActive: Bool
    let hours: [DayHours?]
    let images: [StoredVenueImage]
}

/** 公开的价格方案：订场表头用名字标出每块场地属于哪一档（`<Sport>RatePlan`）。 */
struct CourtRatePlanUi: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int
    let courtIds: [String]
}

struct CourtSlotUi: Hashable, Sendable {
    let startsAt: String
    let endsAt: String
    let status: VenueSlotStatus
    let priceCents: Int?
    let rateLabel: String?
    let occupancy: SlotOccupancy?
    let title: String?

    /** 能订：空着且有价格。 */
    var isOpen: Bool { status == .available && priceCents != nil }
}

/** 订场表的一列（Android `CourtColumnUi`）；[subtitle] 是所属价格方案，[imageURL] 是第一张照片。 */
struct CourtColumnUi: Identifiable, Hashable, Sendable {
    let courtId: String
    let name: String
    let sortOrder: Int
    let slots: [CourtSlotUi]
    var subtitle: String?
    var imageURL: URL?

    var id: String { courtId }
}

/** 球馆本地某一天的「场地 × 时段」（`<Sport>DayGrid`）。 */
struct CourtDayUi: Hashable, Sendable {
    let date: String
    let slotMinutes: Int
    let bookable: Bool
    let availableCount: Int
    let freeCourtCount: Int
    var courts: [CourtColumnUi]

    /** 表头加上价格方案名和第一张照片（WEB `courtMetaById`）。 */
    func withMeta(courts details: [CourtUi], plans: [CourtRatePlanUi], imageURL: (String) -> URL?) -> CourtDayUi {
        var day = self
        day.courts = courts.map { column in
            var column = column
            column.subtitle = plans.first { $0.courtIds.contains(column.courtId) }?.name
            column.imageURL = details.first { $0.id == column.courtId }?.images.min { $0.sortOrder < $1.sortOrder }.flatMap { imageURL($0.imageId) }
            return column
        }
        return day
    }
}

/* ------------------------------ 选场（Android `BoardSelection` + `<Sport>AvailabilitySelection`） ------------------------------ */

/** 场地 id → 选中的时段下标（升序）。不相连的几段保持分开。 */
typealias BoardSelection = [String: [Int]]

/** 一块场地上连着的一段，列在已选栏和确认页上（Android `CourtLineUi`）。 */
struct CourtLineUi: Identifiable, Hashable, Sendable {
    let courtId: String
    let courtName: String
    let startsAt: String
    let endsAt: String
    let minutes: Int
    let priceCents: Int

    var id: String { "\(courtId)|\(startsAt)" }
}

/** 确认页带过去的一段：场地和起止下标（Android `VenueConfirmRange`）。 */
struct VenueConfirmRange: Hashable, Sendable, Codable {
    let courtId: String
    let from: Int
    let to: Int
}

extension BoardSelection {
    func with(_ courtId: String, _ indexes: [Int]) -> BoardSelection {
        var next = self
        next[courtId] = indexes.isEmpty ? nil : indexes
        return next
    }

    var confirmRanges: [VenueConfirmRange] {
        keys.sorted().flatMap { courtId in
            consecutiveRuns(self[courtId] ?? []).map { VenueConfirmRange(courtId: courtId, from: $0.first!, to: $0.last!) }
        }
    }

    init(ranges: [VenueConfirmRange]) {
        var out: BoardSelection = [:]
        for range in ranges {
            out[range.courtId, default: []].append(contentsOf: range.from ... range.to)
        }
        self = out.mapValues { Array(Set($0)).sorted() }
    }

    /** 点一下切换那一格；后点的不会把中间的时段也选上。 */
    func tapping(_ court: CourtColumnUi, _ index: Int) -> BoardSelection {
        let current = self[court.courtId] ?? []
        if current.contains(index) { return with(court.courtId, current.filter { $0 != index }) }
        guard court.slots.indices.contains(index), court.slots[index].isOpen else { return self }
        return with(court.courtId, (current + [index]).sorted())
    }

    /** 拖着涂：加上手指下那一格能订的；不删、不补没经过的空档。 */
    func painting(_ court: CourtColumnUi, _ index: Int) -> BoardSelection {
        guard court.slots.indices.contains(index), court.slots[index].isOpen else { return self }
        let current = self[court.courtId] ?? []
        if current.contains(index) { return self }
        return with(court.courtId, (current + [index]).sorted())
    }

    /** 表重拉以后，去掉已经不能订的格子。 */
    func pruned(_ day: CourtDayUi?) -> BoardSelection {
        guard let day else { return [:] }
        var out: BoardSelection = [:]
        for court in day.courts {
            let kept = (self[court.courtId] ?? []).filter { court.slots.indices.contains($0) && court.slots[$0].isOpen }
            if !kept.isEmpty { out[court.courtId] = kept }
        }
        return out
    }

    /** 每块场地上首尾相接的几段：相邻且时间连着；18:00 和 23:00 还是两条预订。 */
    func lines(_ day: CourtDayUi?) -> [CourtLineUi] {
        guard let day else { return [] }
        return day.courts.flatMap { court in
            runs(court, self[court.courtId] ?? []).map { run in
                let slots = run.map { court.slots[$0] }
                return CourtLineUi(
                    courtId: court.courtId,
                    courtName: court.name,
                    startsAt: slots.first!.startsAt,
                    endsAt: slots.last!.endsAt,
                    minutes: slots.count * day.slotMinutes,
                    priceCents: slots.reduce(0) { $0 + ($1.priceCents ?? 0) }
                )
            }
        }
    }

    /** 去掉某块场地上从 [startsAt] 开始、到 [endsAt] 结束的那一段。 */
    func withoutRun(_ court: CourtColumnUi, startsAt: String, endsAt: String) -> BoardSelection {
        let picked = self[court.courtId] ?? []
        guard let first = picked.first(where: { court.slots.indices.contains($0) && court.slots[$0].startsAt == startsAt }) else { return self }
        var drop = Set<Int>()
        var index = first
        while picked.contains(index) {
            drop.insert(index)
            if court.slots.indices.contains(index), court.slots[index].endsAt == endsAt { break }
            index += 1
        }
        return with(court.courtId, picked.filter { !drop.contains($0) })
    }

    private func runs(_ court: CourtColumnUi, _ indexes: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        for index in indexes.sorted() where court.slots.indices.contains(index) {
            if let previous = out.last?.last, index == previous + 1, court.slots[previous].endsAt == court.slots[index].startsAt {
                out[out.count - 1].append(index)
            } else {
                out.append([index])
            }
        }
        return out
    }
}

private func consecutiveRuns(_ indexes: [Int]) -> [[Int]] {
    var out: [[Int]] = []
    for index in indexes.sorted() {
        if let last = out.last?.last, index == last + 1 {
            out[out.count - 1].append(index)
        } else {
            out.append([index])
        }
    }
    return out
}

/** 每段按球馆的最短 / 最长，再看整单不超过 48 小时。 */
func validateCourtSelection(_ lines: [CourtLineUi], minBookingMinutes: Int, maxBookingMinutes: Int) -> BookingSelectionError? {
    if lines.contains(where: { $0.minutes < minBookingMinutes }) { return .selectionTooShort }
    if lines.contains(where: { $0.minutes > maxBookingMinutes }) { return .selectionTooLong }
    if lines.reduce(0, { $0 + $1.minutes }) > venueBookingTotalMinutesMax { return .selectionTotalTooLong }
    return nil
}

extension BookingSelectionError {
    func text(minBookingMinutes: Int, maxBookingMinutes: Int) -> String {
        switch self {
        case .selectionTooShort: localizedFormat("venue_board_error_too_short", minBookingMinutes)
        case .selectionTooLong: localizedFormat("venue_board_error_too_long", maxBookingMinutes)
        case .selectionTotalTooLong: localizedFormat("venue_board_error_total_too_long", venueBookingTotalMinutesMax / 60)
        }
    }
}

/* ------------------------------ 结账 ------------------------------ */

/** 结账时提交的内容（`<Sport>CheckoutRequest`）。 */
struct CourtCheckoutInput: Sendable {
    let paymentMethod: CourtBookingPaymentMethod
    let lines: [CourtLineUi]
    let contactName: String?
    let contactPhone: String?
    let note: String?
    let bundleId: String?
}

struct CourtCheckoutResultUi: Sendable {
    let bookingId: String
    let status: CourtBookingStatus
    let paymentMethod: CourtBookingPaymentMethod
    let totalAmount: Double
    let currency: String
    let expiresAt: String?
    let payment: PaymentHoldSession?
}

/**
 * 订场要付多少（Android `courtCheckoutPricing`，WEB `CheckoutPanel`）：有效会员付标价的 `100 - discountPercent`%；
 * 时长包按标价整单抵掉（扣分钟，不扣钱），不和会员折扣叠加。整单一起打折，不是各行四舍五入后相加。
 */
struct CourtCheckoutPricing: Sendable {
    let linePayCents: [Int]
    let totalListCents: Int
    let totalPayCents: Int
    /** 标价划掉，下面显示要付的。 */
    let struck: Bool
    /** 打折用的会员卡；不是会员或用时长包付时 nil。 */
    let member: MyMembership?
    let coveredByBundle: Bool

    init(linePriceCents: [Int], membership: MyMembership?, payWithBundle: Bool = false, hasBundle: Bool = false) {
        let active = membership?.status == .active ? membership : nil
        let memberOff = payWithBundle ? 0 : (active?.discountPercent ?? 0).clamped(to: 0 ... 100)
        let covered = payWithBundle && hasBundle
        func pay(_ cents: Int) -> Int {
            if covered { return 0 }
            if memberOff > 0 { return Int((Double(cents) * Double(100 - memberOff) / 100).rounded()) }
            return cents
        }
        let total = linePriceCents.reduce(0, +)
        linePayCents = linePriceCents.map(pay)
        totalListCents = total
        totalPayCents = pay(total)
        struck = covered || memberOff > 0
        member = memberOff > 0 ? active : nil
        coveredByBundle = covered
    }
}

/** 不是会员时，在售等级里折扣最高的一级，用于「成为会员最多省」（WEB `bestDiscountLevel(sellableLevels(grid))`）。 */
func bestUpsellLevel(_ offers: MembershipOffersGrid?, membership: MyMembership?) -> MembershipLevel? {
    guard membership?.status != .active, let grid = offers else { return nil }
    let level = grid.levels
        .filter { level in level.isActive && grid.offers.contains { $0.levelId == level.id && $0.priceAmount != nil } }
        .max { $0.discountPercent < $1.discountPercent }
    return (level?.discountPercent ?? 0) > 0 ? level : nil
}

func upsellSaveCents(_ level: MembershipLevel?, totalCents: Int) -> Int {
    level.map { Int((Double(totalCents) * Double($0.discountPercent) / 100).rounded()) } ?? 0
}

/* ------------------------------ 我的订场 ------------------------------ */

struct CourtBookingSlotUi: Identifiable, Hashable, Sendable {
    let id: String
    let courtId: String
    let courtName: String
    let startsAt: String
    let endsAt: String
    let priceAmount: Double
    let holdsSlot: Bool
}

struct CourtPriceLineUi: Hashable, Sendable {
    let courtId: String
    let startsAt: String
    let endsAt: String
    let amount: Double
    let rateLabel: String?
}

/** 订场人看到的一条预订（`<Sport>MyCourtBooking`）：价格明细、退款政策快照和球馆信息。 */
struct MyCourtBookingUi: Identifiable, Hashable, Sendable {
    let id: String
    let sport: VenueSport
    let venueId: String
    let status: CourtBookingStatus
    let paymentMethod: CourtBookingPaymentMethod
    let startsAt: String
    let endsAt: String
    let totalAmount: Double
    let currency: String
    let refundAmount: Double?
    let refundStatus: String?
    let contactName: String?
    let contactPhone: String?
    let note: String?
    let expiresAt: String?
    let confirmedAt: String?
    let canceledAt: String?
    let canceledBy: CourtBookingCanceledBy?
    let cancelReason: String?
    let expiredAt: String?
    let paidMarkedAt: String?
    let paymentId: String?
    let bundleId: String?
    let bundleMinutes: Int?
    let createdAt: String
    let slots: [CourtBookingSlotUi]
    let priceBreakdown: [CourtPriceLineUi]
    let refundPolicy: CourtRefundPolicy
    let refundPolicyNote: String?
    let refundTiers: [CourtRefundTierUi]
    let venueName: String
    let venueAddress: String
    let venuePhone: String?
    let venueTimezone: String
    let venueLocationLat: Double?
    let venueLocationLng: Double?
    let venueBookingInstructions: String?
    let venueCoverImageId: String?
}

/** 取消前看能退多少（`<Sport>RefundPreview`）。 */
struct CourtRefundPreviewUi: Hashable, Sendable {
    let refundAmount: Double
    let totalAmount: Double
    let providerFeeAmount: Double?
    let currency: String
    let policy: CourtRefundPolicy
    let policyNote: String?
    let tiers: [CourtRefundTierUi]
    let restoreMinutes: Int?
}

/* ------------------------------ 每个运动的读写 ------------------------------ */

/** 订场相关的读写（每个开了球馆入口的运动的 `<Sport>VenueService` 遵守）。 */
protocol VenueSportService: Sendable {
    var sport: VenueSport { get }
    func entry(venueId: String) -> AsyncStream<QueryResponse<CourtEntryUi>>
    func courts(venueId: String) -> AsyncStream<QueryResponse<[CourtUi]>>
    func ratePlans(venueId: String) -> AsyncStream<QueryResponse<[CourtRatePlanUi]>>
    func availability(venueId: String, date: String) -> AsyncStream<QueryResponse<CourtDayUi>>
    func checkout(venueId: String, _ input: CourtCheckoutInput, idempotencyKey: String) async throws -> CourtCheckoutResultUi
    /** 我的订场的前 [limit] 条（日程、活动中心）。 */
    func myBookings(_ key: MyCourtBookingsKey) -> AsyncStream<QueryResponse<[CourtBookingRowUi]>>
    @MainActor func pageMyBookings(upcoming: Bool) -> PagedList<CourtBookingRowUi, Int>
    func myBooking(_ bookingId: String) -> AsyncStream<QueryResponse<MyCourtBookingUi>>
    /** 轮询用：绕过缓存重拉并写回。 */
    func refetchMyBooking(_ bookingId: String) async throws -> MyCourtBookingUi
    func bookingPayment(_ bookingId: String) async throws -> PaymentHoldSession
    func payBooking(_ bookingId: String, paymentMethodId: String) async throws -> PaymentAttempt
    func refundPreview(_ bookingId: String) async throws -> CourtRefundPreviewUi
    func cancelBooking(_ bookingId: String, reason: String?) async throws
}
