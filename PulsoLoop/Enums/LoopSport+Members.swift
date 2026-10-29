import PulsoLinkCore

/* Android `LoopSport.kt` 里取值以外的成员。 */
extension LoopSport: Identifiable {
    var id: String { rawValue }

    /** 这项运动对应的活动类型（Android `eventTypes`，目前每项运动一种）。 */
    var eventType: LoopEventType {
        LoopEventType.fromWire(rawValue)
    }

    static func fromEventType(_ type: LoopEventType) -> LoopSport {
        fromWire(type.rawValue)
    }
}
