import PulsoLinkCore
import SwiftUI

/* 桌游的 DTO 接到通用的活动协议上；其他活动从这里分叉（Scripts/fork_activity.py）。 */

extension BoardGameActivityListItem: ActivityItem {
    var activityType: NearActivityKind { .boardGame }
    var optionLabels: [Text] { [] }
}

extension BoardGameMyRegistrationItem: ActivityTypeRegistrationItem {
    var activityType: NearActivityKind { .boardGame }
    var optionLabels: [Text] { [] }
}

/** 别人主页「参加的」（只要活动字段）。 */
extension BoardGameProfileRegistrationItem: ActivityItem {
    var activityType: NearActivityKind { .boardGame }
    var optionLabels: [Text] { [] }
}

extension BoardGameFullActivity: ActivityTypeFullActivity {
    var activityType: NearActivityKind { .boardGame }

    var paymentMethodList: [ActivityPaymentMethod] {
        paymentMethods.compactMap { method in
            ActivityPaymentKind(rawValue: method.method.rawValue).map { ActivityPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var optionLabels: [Text] { [] }
    var facts: [OptionFact] { [participantsFact(minParticipants: minParticipants, capacity: capacity)] }
}

extension BoardGameRegistration: ActivityTypeRegistration {
    var refund: ActivityRefundStatus? {
        refundStatus.flatMap { ActivityRefundStatus(rawValue: $0.rawValue) }
    }
}
