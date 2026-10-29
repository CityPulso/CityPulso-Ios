/** 支付写操作后的失效事件（Android `PaymentsEventBus`）。 */
public enum PaymentsEvent: Sendable {
    case invalidatePayments
}

public typealias PaymentsEventBus = EventBroadcast<PaymentsEvent>
