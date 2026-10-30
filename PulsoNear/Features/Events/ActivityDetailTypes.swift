import Foundation
import PulsoLinkCore
import SwiftUI

/*
 * 活动详情跨活动类型的形状。Android 每种活动复制一整套详情页；iOS 写一份详情页，各活动类型的 DTO 遵守这里的协议
 * （`Rows/<ActivityType>Rows.swift`），Service 遵守 [NearActivityService]（`Services/<ActivityType>Service+ActivityType.swift`）。
 */

/** 收费方式（各活动类型的 `<ActivityType>PaymentMethodKind` wire 值相同）。 */
enum ActivityPaymentKind: String, Sendable, Hashable {
    case etransfer
    case wechat
    case cash
    case stripe

    var labelKey: LocalizedStringKey {
        switch self {
        case .etransfer: "activity_detail_payment_etransfer"
        case .wechat: "activity_detail_payment_wechat"
        case .cash: "activity_detail_payment_cash"
        case .stripe: "activity_detail_payment_stripe"
        }
    }

    /** 报名弹层里的写法（Android `joinLabelRes`）。 */
    var joinLabel: String {
        switch self {
        case .etransfer: String(localized: "activity_join_registration_payment_methods_etransfer")
        case .wechat: String(localized: "activity_join_registration_payment_methods_wechat")
        case .cash: String(localized: "activity_join_registration_payment_methods_cash")
        case .stripe: String(localized: "activity_join_registration_payment_methods_stripe")
        }
    }
}

struct ActivityPaymentMethod: Hashable, Sendable {
    let kind: ActivityPaymentKind
    let account: String
}

/** 退款进度（各活动类型的 `<ActivityType>RefundStatus` wire 值相同）。 */
enum ActivityRefundStatus: String, Sendable {
    case pending
    case succeeded
    case failed
}

/** 活动页上的一格事实（Android `OptionFact`）。 */
struct OptionFact: Sendable {
    let systemImage: String
    let label: Text
    let value: Text
}

/** 某活动类型的完整活动（`<ActivityType>FullActivity`）。 */
protocol ActivityTypeFullActivity: Sendable {
    var activityType: NearActivityKind { get }
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
    var paymentMethodList: [ActivityPaymentMethod] { get }
    /** 标题下的标签（活动类型特有字段）。 */
    var optionLabels: [Text] { get }
    /** 「详情」里的事实格子。 */
    var facts: [OptionFact] { get }
}

/** 某活动类型的一条报名（`<ActivityType>Registration`）。 */
protocol ActivityTypeRegistration: Sendable {
    var id: String { get }
    var profileId: String { get }
    var status: RegistrationStatus { get }
    var waitlistLatestHoursBeforeStart: Int? { get }
    var playerNote: String? { get }
    var usesPlatformPayment: Bool { get }
    var paymentExpiresAt: String? { get }
    var paidAt: String? { get }
    var refund: ActivityRefundStatus? { get }
    var refundAmount: Double? { get }
    var displayName: String? { get }
    var avatarImageId: String? { get }
    var createdAt: String { get }
}

struct ActivityDetail: Sendable {
    let activity: any ActivityTypeFullActivity
    /** 按 sortOrder 排好的图片 id。 */
    let imageIds: [String]
}

struct RosterPage: Sendable {
    let items: [any ActivityTypeRegistration]
    let total: Int
}

struct JoinResult: Sendable {
    let registration: any ActivityTypeRegistration
    let payment: PaymentHoldActivity?
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

/** 活动详情要的读写（每种活动的 Service 遵守）。 */
protocol ActivityDetailService: Sendable {
    func detail(activityId: String) -> AsyncStream<QueryResponse<ActivityDetail>>
    func roster(activityId: String) -> AsyncStream<QueryResponse<RosterPage>>
    func rosterPage(activityId: String, offset: Int) async throws -> RosterPage
    func prefetchDetail(activityId: String)
    func recordView(activityId: String) async
    func join(activityId: String, waitlistHoursBeforeStart: Int?, playerNote: String?, payByCard: Bool) async throws -> JoinResult
    func exitActivity(activityId: String) async throws -> any ActivityTypeRegistration
    func endActivity(activityId: String) async throws
    /** [mahjongVariant] 只有麻将会发（其他活动没有这个字段，忽略它）。 */
    func patchBasic(activityId: String, title: String?, mahjongVariant: String?, venueName: String?, description: String?, payee: PayeePatch) async throws
    func myRegistrationPayment(activityId: String) async throws -> PaymentHoldActivity
    func payMyRegistration(activityId: String, paymentMethodId: String) async throws -> PaymentAttempt
    func invalidate()
}

/** 人数（最少 – 最多）这一格，每种活动都有（Android `DetailTile(participantsLabel…)`）。 */
func participantsFact(minParticipants: Int, capacity: Int) -> OptionFact {
    OptionFact(systemImage: "person.3", label: Text("activity_detail_field_participants"), value: Text(verbatim: participantsLabel(minParticipants: minParticipants, capacity: capacity)))
}
