import Foundation

/**
 * 带参数的 Android 文案 key（`%1$@` / `%1$lld`，含复数）→ 显示文字，从 App 的 Localizable.xcstrings 取。
 * 不要用 `Text("key \(x)")`：SwiftUI 插值会去找 "key %lld" 这个不存在的 key。
 */
public func localizedFormat(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: arguments)
}
