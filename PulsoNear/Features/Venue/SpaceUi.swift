import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/*
 * 活动类型无关的订场形状（Android `SpaceBoardUi` / `SpaceBookUi` 和各活动类型的 `*AvailabilitySelection`）：每种活动保留自己的
 * DTO，`Services/<ActivityType>VenueService` 把它们换成这里的形状，订场 / 确认 / 我的订场页面只写一份。
 */

/** 门店入口的退款政策（三种活动类型的 `<ActivityType>RefundPolicyType` 取值一样）。 */
enum SpaceRefundPolicy: String, Hashable, Sendable {
    case nonRefundable = "non_refundable"
    case fullRefundMinusProviderFee = "full_refund_minus_provider_fee"
    case tiered

    init(wire: String) {
        self = SpaceRefundPolicy(rawValue: wire) ?? .nonRefundable
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

struct SpaceRefundTierUi: Hashable, Sendable {
    let hoursBeforeStart: Int
    let refundPercent: Int
}

/** 一个活动类型入口：预订规则、退款政策和摘要（`<ActivityType>Entry`）。 */
struct SpaceEntryUi: Hashable, Sendable {
    let status: PublicationStatus
    let bookingWindowDays: Int
    let bookingLeadMinutes: Int
    let slotMinutes: Int
    let minBookingMinutes: Int
    let maxBookingMinutes: Int
    let refundPolicy: SpaceRefundPolicy
    let refundPolicyNote: String?
    let refundTiers: [SpaceRefundTierUi]
    let spaceCount: Int
    let minHourlyPriceAmount: Double?
    let timezone: String
    let currency: String
    let venueStatus: PublicationStatus
}

/** 一张桌台 / 一间包间 / 一个机位（`<ActivityType>Space`）：[kind] 和可容纳人数；[hours] 周一在前，缺的那天休息。 */
struct SpaceUi: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int
    let kind: SpaceKind
    let capacityMin: Int
    let capacityMax: Int
    let description: String?
    let isActive: Bool
    let hours: [DayHours?]
    let images: [StoredVenueImage]
}

/** 公开的价格方案：订场表头用名字标出每块场地属于哪一档（`<ActivityType>RatePlan`）。 */
struct SpaceRatePlanUi: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int
    let spaceIds: [String]
}

struct SpaceSlotUi: Hashable, Sendable {
    let startsAt: String
    let endsAt: String
    let status: VenueSlotStatus
    let priceCents: Int?
    let rateLabel: String?
    let occupancy: SlotOccupancy?

    /** 能订：空着且有价格。 */
    var isOpen: Bool { status == .available && priceCents != nil }
}

/** 订场表的一列（Android `SpaceColumnUi`）；[subtitle] 是所属价格方案，[imageURL] 是第一张照片。 */
struct SpaceColumnUi: Identifiable, Hashable, Sendable {
    let spaceId: String
    let name: String
    let sortOrder: Int
    let slots: [SpaceSlotUi]
    var subtitle: String?
    var imageURL: URL?

    var id: String { spaceId }
}

/** 门店本地某一天的「场地 × 时段」（`<ActivityType>DayGrid`）。 */
struct SpaceDayUi: Hashable, Sendable {
    let date: String
    let slotMinutes: Int
    let bookable: Bool
    let availableCount: Int
    let freeSpaceCount: Int
    var spaces: [SpaceColumnUi]

    /** 表头加上价格方案名和第一张照片（WEB `spaceMetaById`）。 */
    func withMeta(spaces details: [SpaceUi], plans: [SpaceRatePlanUi], imageURL: (String) -> URL?) -> SpaceDayUi {
        var day = self
        day.spaces = spaces.map { column in
            var column = column
            column.subtitle = plans.first { $0.spaceIds.contains(column.spaceId) }?.name
            column.imageURL = details.first { $0.id == column.spaceId }?.images.min { $0.sortOrder < $1.sortOrder }.flatMap { imageURL($0.imageId) }
            return column
        }
        return day
    }
}

/* ------------------------------ 选场（Android `BoardSelection` + `<ActivityType>AvailabilitySelection`） ------------------------------ */

/** 场地 id → 选中的时段下标（升序）。不相连的几段保持分开。 */
typealias BoardSelection = [String: [Int]]

/** 一块场地上连着的一段，列在已选栏和确认页上（Android `SpaceLineUi`）。 */
struct SpaceLineUi: Identifiable, Hashable, Sendable {
    let spaceId: String
    let spaceName: String
    let startsAt: String
    let endsAt: String
    let minutes: Int
    let priceCents: Int

    var id: String { "\(spaceId)|\(startsAt)" }
}

/** 确认页带过去的一段：场地和起止下标（Android `VenueConfirmRange`）。 */
struct VenueConfirmRange: Hashable, Sendable, Codable {
    let spaceId: String
    let from: Int
    let to: Int
}

extension BoardSelection {
    func with(_ spaceId: String, _ indexes: [Int]) -> BoardSelection {
        var next = self
        next[spaceId] = indexes.isEmpty ? nil : indexes
        return next
    }

    var confirmRanges: [VenueConfirmRange] {
        keys.sorted().flatMap { spaceId in
            consecutiveRuns(self[spaceId] ?? []).map { VenueConfirmRange(spaceId: spaceId, from: $0.first!, to: $0.last!) }
        }
    }

    init(ranges: [VenueConfirmRange]) {
        var out: BoardSelection = [:]
        for range in ranges {
            out[range.spaceId, default: []].append(contentsOf: range.from ... range.to)
        }
        self = out.mapValues { Array(Set($0)).sorted() }
    }

    /** 点一下切换那一格；后点的不会把中间的时段也选上。 */
    func tapping(_ space: SpaceColumnUi, _ index: Int) -> BoardSelection {
        let current = self[space.spaceId] ?? []
        if current.contains(index) { return with(space.spaceId, current.filter { $0 != index }) }
        guard space.slots.indices.contains(index), space.slots[index].isOpen else { return self }
        return with(space.spaceId, (current + [index]).sorted())
    }

    /** 拖着涂：加上手指下那一格能订的；不删、不补没经过的空档。 */
    func painting(_ space: SpaceColumnUi, _ index: Int) -> BoardSelection {
        guard space.slots.indices.contains(index), space.slots[index].isOpen else { return self }
        let current = self[space.spaceId] ?? []
        if current.contains(index) { return self }
        return with(space.spaceId, (current + [index]).sorted())
    }

    /** 表重拉以后，去掉已经不能订的格子。 */
    func pruned(_ day: SpaceDayUi?) -> BoardSelection {
        guard let day else { return [:] }
        var out: BoardSelection = [:]
        for space in day.spaces {
            let kept = (self[space.spaceId] ?? []).filter { space.slots.indices.contains($0) && space.slots[$0].isOpen }
            if !kept.isEmpty { out[space.spaceId] = kept }
        }
        return out
    }

    /** 每块场地上首尾相接的几段：相邻且时间连着；18:00 和 23:00 还是两条预订。 */
    func lines(_ day: SpaceDayUi?) -> [SpaceLineUi] {
        guard let day else { return [] }
        return day.spaces.flatMap { space in
            runs(space, self[space.spaceId] ?? []).map { run in
                let slots = run.map { space.slots[$0] }
                return SpaceLineUi(
                    spaceId: space.spaceId,
                    spaceName: space.name,
                    startsAt: slots.first!.startsAt,
                    endsAt: slots.last!.endsAt,
                    minutes: slots.count * day.slotMinutes,
                    priceCents: slots.reduce(0) { $0 + ($1.priceCents ?? 0) }
                )
            }
        }
    }

    /** 去掉某块场地上从 [startsAt] 开始、到 [endsAt] 结束的那一段。 */
    func withoutRun(_ space: SpaceColumnUi, startsAt: String, endsAt: String) -> BoardSelection {
        let picked = self[space.spaceId] ?? []
        guard let first = picked.first(where: { space.slots.indices.contains($0) && space.slots[$0].startsAt == startsAt }) else { return self }
        var drop = Set<Int>()
        var index = first
        while picked.contains(index) {
            drop.insert(index)
            if space.slots.indices.contains(index), space.slots[index].endsAt == endsAt { break }
            index += 1
        }
        return with(space.spaceId, picked.filter { !drop.contains($0) })
    }

    private func runs(_ space: SpaceColumnUi, _ indexes: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        for index in indexes.sorted() where space.slots.indices.contains(index) {
            if let previous = out.last?.last, index == previous + 1, space.slots[previous].endsAt == space.slots[index].startsAt {
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

/** 每段按门店的最短 / 最长，再看整单不超过 48 小时。 */
func validateSpaceSelection(_ lines: [SpaceLineUi], minBookingMinutes: Int, maxBookingMinutes: Int) -> BookingSelectionError? {
    if lines.contains(where: { $0.minutes < minBookingMinutes }) { return .selectionTooShort }
    if lines.contains(where: { $0.minutes > maxBookingMinutes }) { return .selectionTooLong }
    if lines.reduce(0, { $0 + $1.minutes }) > venueBookingTotalMinutesMax { return .selectionTotalTooLong }
    return nil
}

extension BookingSelectionError {
    func text(minBookingMinutes: Int, maxBookingMinutes: Int) -> String {
        switch self {
        case .selectionTooShort: localizedFormat("venue_board_error_too_short", String(minBookingMinutes))
        case .selectionTooLong: localizedFormat("venue_board_error_too_long", String(maxBookingMinutes))
        case .selectionTotalTooLong: localizedFormat("venue_board_error_total_too_long", String(venueBookingTotalMinutesMax / 60))
        }
    }
}

/* ------------------------------ 结账 ------------------------------ */

/** 结账时提交的内容（`<ActivityType>CheckoutRequest`）。 */
struct SpaceCheckoutInput: Sendable {
    let paymentMethod: SpaceBookingPaymentMethod
    let lines: [SpaceLineUi]
    let contactName: String?
    let contactPhone: String?
    let note: String?
}

struct SpaceCheckoutResultUi: Sendable {
    let bookingId: String
    let status: SpaceBookingStatus
    let paymentMethod: SpaceBookingPaymentMethod
    let totalAmount: Double
    let currency: String
    let expiresAt: String?
    let payment: PaymentHoldActivity?
}

/**
 * 订场要付多少（Android `spaceCheckoutPricing`，WEB `CheckoutPanel`）：有效会员付标价的 `100 - discountPercent`%；
 * 时长包按标价整单抵掉（扣分钟，不扣钱），不和会员折扣叠加。整单一起打折，不是各行四舍五入后相加。
 */
struct SpaceCheckoutPricing: Sendable {
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

struct SpaceBookingSlotUi: Identifiable, Hashable, Sendable {
    let id: String
    let spaceId: String
    let spaceName: String
    let startsAt: String
    /** 到店开台还没结束的是 nil。 */
    let endsAt: String?
    let priceAmount: Double
    let holdsSlot: Bool
}

struct SpacePriceLineUi: Hashable, Sendable {
    let spaceId: String
    let startsAt: String
    let endsAt: String
    let amount: Double
    let rateLabel: String?
}

/** 订场人看到的一条预订（`<ActivityType>MySpaceBooking`）：价格明细、退款政策快照和门店信息。 */
struct MySpaceBookingUi: Identifiable, Hashable, Sendable {
    let id: String
    let activityType: VenueActivityType
    let venueId: String
    /** 预订（定好时间）还是到店开台（[endsAt] 结束前为 nil）。 */
    let mode: SpaceBookingMode
    let status: SpaceBookingStatus
    let paymentMethod: SpaceBookingPaymentMethod
    let startsAt: String
    let endsAt: String?
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
    let canceledBy: SpaceBookingCanceledBy?
    let cancelReason: String?
    let expiredAt: String?
    let paidMarkedAt: String?
    let paymentId: String?
    let createdAt: String
    let slots: [SpaceBookingSlotUi]
    let priceBreakdown: [SpacePriceLineUi]
    let refundPolicy: SpaceRefundPolicy
    let refundPolicyNote: String?
    let refundTiers: [SpaceRefundTierUi]
    let venueName: String
    let venueAddress: String
    let venuePhone: String?
    let venueTimezone: String
    let venueLocationLat: Double?
    let venueLocationLng: Double?
    let venueBookingInstructions: String?
    let venueCoverImageId: String?
}

/** 取消前看能退多少（`<ActivityType>RefundPreview`）。 */
struct SpaceRefundPreviewUi: Hashable, Sendable {
    let refundAmount: Double
    let totalAmount: Double
    let providerFeeAmount: Double?
    let currency: String
    let policy: SpaceRefundPolicy
    let policyNote: String?
    let tiers: [SpaceRefundTierUi]
}

/* ------------------------------ 每种活动的读写 ------------------------------ */

/** 我的预约的读写，桌台类和场次类门店都一样（每种门店类型的 `<ActivityType>VenueService` 遵守）。 */
protocol VenueBookingService: Sendable {
    var activityType: VenueActivityType { get }
    /** 我的预约的前 [limit] 条（日程、活动中心）。 */
    func myBookings(_ key: MySpaceBookingsKey) -> AsyncStream<QueryResponse<[SpaceBookingRowUi]>>
    @MainActor func pageMyBookings(upcoming: Bool) -> PagedList<SpaceBookingRowUi, Int>
    func myBooking(_ bookingId: String) -> AsyncStream<QueryResponse<MySpaceBookingUi>>
    /** 轮询用：绕过缓存重拉并写回。 */
    func refetchMyBooking(_ bookingId: String) async throws -> MySpaceBookingUi
    func bookingPayment(_ bookingId: String) async throws -> PaymentHoldActivity
    func payBooking(_ bookingId: String, paymentMethodId: String) async throws -> PaymentAttempt
    func refundPreview(_ bookingId: String) async throws -> SpaceRefundPreviewUi
    func cancelBooking(_ bookingId: String, reason: String?) async throws
}

/** 按桌台 / 包间 / 机位、按时段订的门店（桌游、麻将、KTV、台球、电竞；Android `VenueBookingTemplate.SPACE`）。 */
protocol VenueActivityTypeService: VenueBookingService {
    func entry(venueId: String) -> AsyncStream<QueryResponse<SpaceEntryUi>>
    func spaces(venueId: String) -> AsyncStream<QueryResponse<[SpaceUi]>>
    func ratePlans(venueId: String) -> AsyncStream<QueryResponse<[SpaceRatePlanUi]>>
    func availability(venueId: String, date: String) -> AsyncStream<QueryResponse<SpaceDayUi>>
    func checkout(venueId: String, _ input: SpaceCheckoutInput, idempotencyKey: String) async throws -> SpaceCheckoutResultUi
}
