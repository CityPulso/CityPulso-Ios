import PulsoLinkCore

/* Android `NearActivityKind.kt` 里取值以外的成员。 */
extension NearActivityKind: Identifiable {
    var id: String { rawValue }

    /** 这种活动对应的活动类型（Android `activityTypes`，目前每种一个）。 */
    var activityType: NearActivityType {
        NearActivityType.fromWire(rawValue)
    }

    static func fromActivityType(_ type: NearActivityType) -> NearActivityKind {
        fromWire(type.rawValue)
    }
}

extension NearActivityType {
    /** 线上的活动类型对应的页面类型（详情、图标、服务都按它分）。 */
    var kind: NearActivityKind { NearActivityKind.fromActivityType(self) }
}
