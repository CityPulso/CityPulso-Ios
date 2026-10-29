import Foundation

/* 账单偏好枚举——wire 值与 PulsoLink-Package `enums/billing.ts` 逐一对齐。 */

/** 收据弹窗锚点位置（用户偏好 billing.receiptPosition）。 */
public enum BillingReceiptPosition: String, WireEnum {
    case bottomRight = "bottom-right"
    case bottomLeft = "bottom-left"
    case topRight = "top-right"
    case topLeft = "top-left"

    public static let fallback: BillingReceiptPosition = .bottomRight
}
