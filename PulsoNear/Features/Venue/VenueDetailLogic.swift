import Foundation
import PulsoLinkCore

extension VenueDetail {
    /** 已上线的活动类型入口（工作人员能看到草稿入口，普通成员一律只认已上线的）。 */
    var publishedActivityTypes: [VenueActivityType] {
        activityTypeEntries.filter { $0.status == .published }.map(\.activityType)
    }

    var displayName: String { building.name }

    /** 所有入口的桌台总数。 */
    var totalSpaceCount: Int { activityTypeEntries.reduce(0) { $0 + $1.spaceCount } }

    /** 所有入口里最低的起步时价；都没定价时 nil。 */
    var lowestHourlyPrice: Double? { activityTypeEntries.compactMap(\.minHourlyPriceAmount).min() }

    /** 预约接受的方式，在线付款在前（WEB `CheckoutPanel`）。 */
    var acceptedMethods: [SpaceBookingPaymentMethod] {
        [.platform, .phone, .offline].filter { method in
            switch method {
            case .platform: acceptsPlatform
            case .phone: acceptsPhone
            case .offline: acceptsOffline
            }
        }
    }

    var acceptedMembershipMethods: [MembershipPaymentMethod] {
        [.platform, .phone, .offline].filter { method in
            switch method {
            case .platform: membershipAcceptsPlatform
            case .phone: membershipAcceptsPhone
            case .offline: membershipAcceptsOffline
            }
        }
    }
}
