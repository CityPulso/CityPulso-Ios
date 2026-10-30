import Foundation
import PulsoLinkCore
import SwiftUI

/*
 * 活动详情跨运动的形状。Android 每个运动复制一整套详情页；iOS 写一份详情页，各运动的 DTO 遵守这里的协议
 * （`Rows/<Sport>Rows.swift`），Service 遵守 [LoopSportService]（`Services/<Sport>Service+Sport.swift`）。
 */

/** 收费方式（各运动的 `<Sport>PaymentMethodKind` wire 值相同）。 */
enum EventPaymentKind: String, Sendable, Hashable {
    case etransfer
    case wechat
    case cash
    case stripe

    var labelKey: LocalizedStringKey {
        switch self {
        case .etransfer: "event_detail_payment_etransfer"
        case .wechat: "event_detail_payment_wechat"
        case .cash: "event_detail_payment_cash"
        case .stripe: "event_detail_payment_stripe"
        }
    }

    /** 报名弹层里的写法（Android `joinLabelRes`）。 */
    var joinLabel: String {
        switch self {
        case .etransfer: String(localized: "event_join_registration_payment_methods_etransfer")
        case .wechat: String(localized: "event_join_registration_payment_methods_wechat")
        case .cash: String(localized: "event_join_registration_payment_methods_cash")
        case .stripe: String(localized: "event_join_registration_payment_methods_stripe")
        }
    }
}

struct EventPaymentMethod: Hashable, Sendable {
    let kind: EventPaymentKind
    let account: String
}

/** 退款进度（各运动的 `<Sport>RefundStatus` wire 值相同）。 */
enum EventRefundStatus: String, Sendable {
    case pending
    case succeeded
    case failed
}

struct EventEquipment: Hashable, Sendable {
    let name: String
    let icon: String

    /** Lucide 图标名 → SF Symbol（Android `catalogIcon`）。 */
    var systemImage: String { catalogSystemImage(icon) }
}

/** 活动页上的一格事实（Android `OptionFact`）。 */
struct OptionFact: Sendable {
    let systemImage: String
    let label: Text
    let value: Text
}

/** 某运动的完整活动（`<Sport>FullEvent`）。 */
protocol SportFullEvent: Sendable {
    var sport: LoopSport { get }
    var id: String { get }
    var profileId: String { get }
    var title: String { get }
    var description: String? { get }
    var venueName: String? { get }
    var address: String? { get }
    var startsAt: String { get }
    var endsAt: String { get }
    var locationLat: Double? { get }
    var locationLng: Double? { get }
    var capacity: Int { get }
    var waitlistCapacity: Int { get }
    var isFree: Bool { get }
    var priceAmount: Double? { get }
    var currency: String { get }
    var payeePaymentAccountId: String? { get }
    var allowsFreeExit: Bool { get }
    var freeExitHoursBeforeStart: Int? { get }
    var isEnded: Bool { get }
    var view: Int { get }
    var participatingCount: Int { get }
    var waitlistedCount: Int { get }
    var pendingExitCount: Int { get }
    var awaitingPaymentCount: Int { get }
    var paymentMethodList: [EventPaymentMethod] { get }
    var equipmentList: [EventEquipment] { get }
    /** 标题下的标签（运动特有字段）。 */
    var optionLabels: [Text] { get }
    /** 「详情」里的事实格子。 */
    var facts: [OptionFact] { get }
}

/** 某运动的一条报名（`<Sport>Registration`）。 */
protocol SportRegistration: Sendable {
    var id: String { get }
    var profileId: String { get }
    var status: RegistrationStatus { get }
    var waitlistLatestHoursBeforeStart: Int? { get }
    var playerNote: String? { get }
    var usesPlatformPayment: Bool { get }
    var paymentExpiresAt: String? { get }
    var paidAt: String? { get }
    var refund: EventRefundStatus? { get }
    var refundAmount: Double? { get }
    var displayName: String? { get }
    var avatarImageId: String? { get }
    var createdAt: String { get }
}

struct EventDetail: Sendable {
    let event: any SportFullEvent
    /** 按 sortOrder 排好的图片 id。 */
    let imageIds: [String]
}

struct RosterPage: Sendable {
    let items: [any SportRegistration]
    let total: Int
}

struct JoinResult: Sendable {
    let registration: any SportRegistration
    let payment: PaymentHoldSession?
}

/** 改收款账户：不变 / 不收刷卡 / 换成某个账户（Android 用 JsonNull / JsonPrimitive 表达）。 */
enum PayeePatch: Sendable {
    case unchanged
    case none
    case account(String)

    var wire: WireJSON? {
        switch self {
        case .unchanged: nil
        case .none: .null
        case let .account(id): .string(id)
        }
    }
}

/** 活动详情要的读写（每个运动的 Service 遵守）。 */
protocol SportEventDetailService: Sendable {
    func detail(eventId: String) -> AsyncStream<QueryResponse<EventDetail>>
    func roster(eventId: String) -> AsyncStream<QueryResponse<RosterPage>>
    func rosterPage(eventId: String, offset: Int) async throws -> RosterPage
    func prefetchDetail(eventId: String)
    func recordView(eventId: String) async
    func join(eventId: String, waitlistHoursBeforeStart: Int?, playerNote: String?, payByCard: Bool) async throws -> JoinResult
    func exitEvent(eventId: String) async throws -> any SportRegistration
    func endEvent(eventId: String) async throws
    func patchBasic(eventId: String, title: String?, venueName: String?, description: String?, payee: PayeePatch) async throws
    func myRegistrationPayment(eventId: String) async throws -> PaymentHoldSession
    func payMyRegistration(eventId: String, paymentMethodId: String) async throws -> PaymentAttempt
    func invalidate()
}

/** 球拍类的事实格子：赛制、组别、场地数、每场人数。 */
func racketFacts(matchFormat: MatchFormat, eligibilityDivision: EligibilityDivision, courtCount: Int, playersPerCourt: Int) -> [OptionFact] {
    [
        OptionFact(systemImage: "figure.badminton", label: Text("event_detail_field_format"), value: Text(matchFormat.labelKey)),
        OptionFact(systemImage: "figure.dress.line.vertical.figure", label: Text("event_detail_field_division"), value: Text(eligibilityDivision.labelKey)),
        OptionFact(systemImage: "sportscourt", label: Text("event_detail_field_courts"), value: Text(verbatim: "\(courtCount)")),
        OptionFact(systemImage: "number", label: Text("event_detail_field_players_per_court"), value: Text(verbatim: "\(playersPerCourt)")),
    ]
}
