import Foundation
import PulsoLinkCore

/** 列表和详情共用的时长包字段（Android `BundleHolding`）。 */
protocol BundleHolding {
    var status: BundleStatus { get }
    var name: String { get }
    var includedMinutes: Int { get }
    var remainingMinutes: Int { get }
    var validDays: Int? { get }
    var expiresAt: String? { get }
    var sports: [VenueSport] { get }
    var venueName: String { get }
    var venueAddress: String { get }
    var venueTimezone: String { get }
    var venueCoverImageId: String? { get }
}

extension MyBundle: BundleHolding {}
extension MyBundleDetail: BundleHolding {}

/* 时长包纯逻辑（Android `features/bundle/logic`，WEB `features/bundle/logic`）。 */

extension BundleHolding {
    /** 展示状态：生效中但已过期算过期，余额为 0 算用完。 */
    func state(now: Date = .now) -> BundleState {
        switch status {
        case .pending: return .pending
        case .canceled: return .canceled
        case .active:
            if let expires = DateTimeFormatters.parseInstant(expiresAt), expires <= now { return .expired }
            return remainingMinutes <= 0 ? .usedUp : .active
        }
    }

    /** 剩余分钟占总分钟的比例，0–1。 */
    var balanceShare: Double {
        includedMinutes > 0 ? (Double(remainingMinutes) / Double(includedMinutes)).clamped(to: 0 ... 1) : 0
    }

    /** 现在能不能付一笔 [sport] 的 [minutes] 分钟订场：必须全部覆盖，不支持部分抵扣。 */
    func canPayBooking(_ sport: VenueSport, minutes: Int, now: Date = .now) -> Bool {
        state(now: now) == .active && sports.contains(sport) && minutes > 0 && remainingMinutes >= minutes
    }
}

/** 包里一小时的价格。 */
func bundleHourlyAmount(_ priceAmount: Double, includedMinutes: Int) -> Double {
    includedMinutes > 0 ? priceAmount * 60 / Double(includedMinutes) : 0
}

/** 和按场地时价打同样分钟相比省下的整数百分比；不省钱时 nil。 */
func bundleSavingPercent(_ priceAmount: Double, includedMinutes: Int, hourlyPrice: Double?) -> Int? {
    guard let hourlyPrice, hourlyPrice > 0, includedMinutes > 0 else { return nil }
    let regular = hourlyPrice * Double(includedMinutes) / 60
    let percent = Int(((regular - priceAmount) * 100 / regular + 1e-9).rounded(.down))
    return percent > 0 ? percent : nil
}

extension BundleOffer {
    /** 生效等级的会员价，高等级在前；没开会员价时为空。 */
    var activeMemberPrices: [BundleMemberPrice] {
        memberPricingEnabled ? memberPrices.filter(\.levelIsActive).sorted { $0.rank > $1.rank } : []
    }

    /** 比原价低的最低会员价（卡片上的「会员价起」）。 */
    var lowestMemberPrice: BundleMemberPrice? {
        activeMemberPrices.filter { $0.priceAmount < priceAmount }.min { $0.priceAmount < $1.priceAmount }
    }
}

extension [BundleOffer] {
    /** 上架的时长包，按球馆的顺序。 */
    var shown: [BundleOffer] { filter(\.isShown).sorted { $0.sortOrder < $1.sortOrder } }
}
