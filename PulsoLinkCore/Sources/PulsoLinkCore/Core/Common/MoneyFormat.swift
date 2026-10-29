import Foundation

/** 金额 + ISO 4217 币种 → 本地化货币串（Android `formatMoney`、WEB `formatMoney`）；未知币种按 [locale] 的币种显示。 */
public func formatMoney(_ amount: Double, currency: String, locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = locale
    let code = currency.uppercased()
    if Locale.commonISOCurrencyCodes.contains(code) {
        formatter.currencyCode = code
    }
    return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
}

/** 剩余秒数 → `m:ss`（WEB `formatCountdown`）。 */
public func formatCountdown(_ seconds: Int) -> String {
    let safe = max(seconds, 0)
    return String(format: "%d:%02d", safe / 60, safe % 60)
}
