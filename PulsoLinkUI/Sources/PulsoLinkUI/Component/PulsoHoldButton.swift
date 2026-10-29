import SwiftUI

/** 按住多久才算确认（Android `PULSO_HOLD_DURATION_MILLIS`）。 */
public let pulsoHoldSeconds = 1.5

/**
 * 按住确认的危险操作按钮（Android `PulsoHoldButton`）：按住时从左往右填满，填满才触发 [onComplete]，中途松手回退。
 * [loading] 时显示转圈、不响应。
 */
public struct PulsoHoldButton: View {
    private let title: LocalizedStringKey
    private let loading: Bool
    private let onComplete: () -> Void

    @GestureState private var pressing = false
    @State private var progress: CGFloat = 0

    public init(_ title: LocalizedStringKey, loading: Bool = false, onComplete: @escaping () -> Void) {
        self.title = title
        self.loading = loading
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            Capsule().fill(Color.red.opacity(0.18))
            GeometryReader { proxy in
                Capsule().fill(Color.red).frame(width: proxy.size.width * progress)
            }
            if loading {
                ProgressView().tint(.white)
            } else {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(progress > 0.5 ? Color.white : Color.red)
            }
        }
        .frame(height: 50)
        .clipShape(.capsule)
        .contentShape(.capsule)
        .gesture(
            LongPressGesture(minimumDuration: pulsoHoldSeconds)
                .updating($pressing) { value, state, _ in state = value }
                .onEnded { _ in
                    progress = 1
                    onComplete()
                }
        )
        .onChange(of: pressing) { _, pressing in
            guard !loading else { return }
            if pressing {
                withAnimation(.linear(duration: pulsoHoldSeconds)) { progress = 1 }
            } else if progress < 1 {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .onChange(of: loading) { _, loading in
            if !loading { progress = 0 }
        }
        .disabled(loading)
        .sensoryFeedback(.impact, trigger: progress == 1)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onComplete() }
    }
}
