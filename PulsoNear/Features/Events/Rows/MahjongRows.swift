import PulsoLinkCore
import SwiftUI

/* 麻将的 DTO 接到通用的活动协议上。麻将多一个规则（`mahjongVariant`），所以这个文件手写，不从桌游分叉。 */

extension MahjongActivityListItem: ActivityItem {
    var activityType: NearActivityKind { .mahjong }
    var optionLabels: [Text] { [] }
}

extension MahjongMyRegistrationItem: ActivityTypeRegistrationItem {
    var activityType: NearActivityKind { .mahjong }
    var optionLabels: [Text] { [] }
}

/** 别人主页「参加的」（只要活动字段）。 */
extension MahjongProfileRegistrationItem: ActivityItem {
    var activityType: NearActivityKind { .mahjong }
    var optionLabels: [Text] { [] }
}

extension MahjongFullActivity: ActivityTypeFullActivity {
    var activityType: NearActivityKind { .mahjong }

    var paymentMethodList: [ActivityPaymentMethod] {
        paymentMethods.compactMap { method in
            ActivityPaymentKind(rawValue: method.method.rawValue).map { ActivityPaymentMethod(kind: $0, account: method.account) }
        }
    }

    var optionLabels: [Text] { [] }
    var facts: [OptionFact] {
        var facts = [participantsFact(minParticipants: minParticipants, capacity: capacity)]
        // 规则（Android `DetailTile(Casino, mahjongVariant, create_mahjong_variant_label)`）。
        if !mahjongVariant.trimmingCharacters(in: .whitespaces).isEmpty {
            facts.append(OptionFact(systemImage: "dice", label: Text("create_mahjong_variant_label"), value: Text(verbatim: mahjongVariant)))
        }
        return facts
    }
}

extension MahjongRegistration: ActivityTypeRegistration {
    var refund: ActivityRefundStatus? {
        refundStatus.flatMap { ActivityRefundStatus(rawValue: $0.rawValue) }
    }
}
