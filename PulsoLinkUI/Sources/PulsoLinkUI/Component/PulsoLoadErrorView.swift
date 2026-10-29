import PulsoLinkCore
import SwiftUI

/** 整页加载失败（对应 Android `PulsoLoadErrorPage`）：按失败类别给标题和说明，加一个「再试一次」。 */
public struct PulsoLoadErrorView: View {
    private let error: UiError
    private let retry: () -> Void

    public init(_ error: UiError, retry: @escaping () -> Void) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label {
                Text(error.kind.titleKey, bundle: .module)
            } icon: {
                Image(systemName: error.kind.systemImage)
            }
        } description: {
            if let message = error.message {
                Text(message)
            } else {
                Text(error.kind.subtitleKey, bundle: .module)
            }
        } actions: {
            Button(action: retry) {
                Text("pulso_ui_retry", bundle: .module)
            }
            .buttonStyle(.glassProminent)
        }
    }
}

extension LoadErrorKind {
    fileprivate var titleKey: LocalizedStringKey {
        switch self {
        case .notFound: "pulso_ui_load_error_not_found_title"
        case .unauthorized: "pulso_ui_load_error_unauthorized_title"
        case .timeout: "pulso_ui_load_error_timeout_title"
        case .offline: "pulso_ui_load_error_offline_title"
        case .server: "pulso_ui_load_error_server_title"
        case .unknown: "pulso_ui_load_error_unknown_title"
        }
    }

    fileprivate var subtitleKey: LocalizedStringKey {
        switch self {
        case .notFound: "pulso_ui_load_error_not_found_subtitle"
        case .unauthorized: "pulso_ui_load_error_unauthorized_subtitle"
        case .timeout: "pulso_ui_load_error_timeout_subtitle"
        case .offline: "pulso_ui_load_error_offline_subtitle"
        case .server: "pulso_ui_load_error_server_subtitle"
        case .unknown: "pulso_ui_load_error_unknown_subtitle"
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .notFound: "magnifyingglass"
        case .unauthorized: "lock"
        case .timeout: "timer"
        case .offline: "wifi.slash"
        case .server: "icloud.slash"
        case .unknown: "exclamationmark.triangle"
        }
    }
}
