import PulsoLinkCore
import SwiftUI

/** 「有数据，但最近一次刷新失败」的细条（Android `PulsoErrorBanner`）：内容留在下面，这里只说明是旧的并给重试。 */
public struct PulsoErrorBanner: View {
    private let error: UiError
    private let retry: () -> Void

    public init(_ error: UiError, retry: @escaping () -> Void) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: error.kind.systemImage).foregroundStyle(.secondary)
            Text(shortKey, bundle: .module).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) { Text("pulso_ui_retry", bundle: .module) }
                .buttonStyle(.borderless)
                .font(.footnote.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    /** 不明原因没有通用短句，用「数据可能不是最新」。 */
    private var shortKey: LocalizedStringKey {
        switch error.kind {
        case .notFound: "pulso_ui_error_not_found"
        case .unauthorized: "pulso_ui_error_unauthorized"
        case .timeout: "pulso_ui_error_timeout"
        case .offline: "pulso_ui_error_offline"
        case .server: "pulso_ui_error_server"
        case .unknown: "pulso_ui_stale_banner"
        }
    }
}
