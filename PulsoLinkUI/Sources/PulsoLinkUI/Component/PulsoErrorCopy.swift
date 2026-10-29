import PulsoLinkCore
import SwiftUI

/* 失败文案（对应 Android `PulsoErrorCopy`）：每种失败类别一句通用短句，所有报错的地方共用。 */

extension LoadErrorKind {
    /** 通用短句；unknown 没有，用页面自己的 fallback（如「无法保存」）更有用。 */
    public var shortText: String? {
        switch self {
        case .notFound: String(localized: "pulso_ui_error_not_found", bundle: .module)
        case .unauthorized: String(localized: "pulso_ui_error_unauthorized", bundle: .module)
        case .timeout: String(localized: "pulso_ui_error_timeout", bundle: .module)
        case .offline: String(localized: "pulso_ui_error_offline", bundle: .module)
        case .server: String(localized: "pulso_ui_error_server", bundle: .module)
        case .unknown: nil
        }
    }
}

extension UiError {
    /** 显示文字，处处同一优先级：后端业务文案 → 类别通用短句 → 页面的 [fallback]。 */
    public func text(fallback: String) -> String {
        message ?? kind.shortText ?? fallback
    }
}
