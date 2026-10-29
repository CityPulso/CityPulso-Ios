import PulsoLinkCore
import SwiftUI

/**
 * App 级的一次性提示（对应 Android `UiMessageBus` + 全局 snackbar）：操作失败、成功、说明。
 * 页面加载失败不走这里，那是整页的错误视图。文案 key 都在各 App 的 Localizable.xcstrings。
 */
@MainActor
@Observable
public final class PulsoMessageCenter {
    public enum Tone: Sendable {
        case error
        case success
        case info
    }

    public struct Message: Identifiable, Equatable {
        public let id = UUID()
        public let tone: Tone
        public let text: String
    }

    public static let shared = PulsoMessageCenter()
    private static let visibleFor = Duration.seconds(3)

    public private(set) var current: Message?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /** 失败：后端文案 → 类别通用短句 → [fallback]。 */
    public func error(_ error: any Error, fallback: String.LocalizationValue) {
        show(.error, UiError(error).text(fallback: String(localized: fallback)))
    }

    /** 查询层已经归类好的失败（[QueryResponse.error]）。 */
    public func error(_ error: UiError, fallback: String.LocalizationValue) {
        show(.error, error.text(fallback: String(localized: fallback)))
    }

    /** 本地校验或规则提示（没有网络失败）。 */
    public func error(_ key: String.LocalizationValue) {
        show(.error, String(localized: key))
    }

    public func success(_ key: String.LocalizationValue) {
        show(.success, String(localized: key))
    }

    public func info(_ key: String.LocalizationValue) {
        show(.info, String(localized: key))
    }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    private func show(_ tone: Tone, _ text: String) {
        dismissTask?.cancel()
        current = Message(tone: tone, text: text)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }
}

/** 顶部的玻璃胶囊提示，点一下收起。 */
struct PulsoMessageHost: ViewModifier {
    @State private var center = PulsoMessageCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = center.current {
                Label {
                    Text(message.text)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: message.tone.systemImage)
                        .foregroundStyle(message.tone.color)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .onTapGesture { center.dismiss() }
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(message.id)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: center.current)
    }
}

extension PulsoMessageCenter.Tone {
    fileprivate var systemImage: String {
        switch self {
        case .error: "exclamationmark.circle.fill"
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .error: .red
        case .success: .green
        case .info: .accentColor
        }
    }
}

extension View {
    /** 挂在根视图上：全局提示从屏幕顶部滑出。 */
    public func pulsoMessageHost() -> some View {
        modifier(PulsoMessageHost())
    }
}
