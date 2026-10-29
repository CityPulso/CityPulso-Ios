import Foundation

/** 资料里的网站转成能打开的链接：空 → nil，裸域名补 `https://`（对应 Android `normalizeWebsiteHref`）。 */
func normalizedWebsiteURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()
    return URL(string: lower.hasPrefix("https://") || lower.hasPrefix("http://") ? trimmed : "https://\(trimmed)")
}
