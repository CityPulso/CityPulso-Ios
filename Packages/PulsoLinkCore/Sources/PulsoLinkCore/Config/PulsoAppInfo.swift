import Foundation

/** 宿主 App 的 Info.plist 配置（`PulsoApiBaseURL` 由 xcconfig 的 `PULSO_API_BASE_URL` 写入）。 */
public enum PulsoAppInfo {
    /** 必填，无默认：缺了说明 `Config/Local.xcconfig` 没配，直接崩比连错服务器好。 */
    public static var apiBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PulsoApiBaseURL") as? String,
              let url = URL(string: raw), url.scheme != nil
        else {
            fatalError("PulsoApiBaseURL missing; set PULSO_API_BASE_URL in Config/Local.xcconfig")
        }
        return url
    }

    public static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
