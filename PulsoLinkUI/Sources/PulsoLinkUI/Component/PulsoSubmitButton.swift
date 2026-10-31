import SwiftUI

/** 提交按钮所处阶段：就绪、进行中、成功（画勾）、失败（重新展开）（Android `SubmitPhase`）。 */
public enum SubmitPhase: Sendable {
    case idle, loading, success, error

    /** 进行中或正在画勾：不能再提交。 */
    public var busy: Bool { self == .loading || self == .success }
}

/**
 * 驱动一个变形提交按钮（Android `SubmitAction`）：[run] 运行中是 loading，完成后 success；
 * 后续动作（进 App、关页面）等按钮画完勾、调 [successShown] 才执行。失败交给 onFailure，阶段变 error，按钮抖一下重新展开。
 */
@MainActor
@Observable
public final class SubmitAction {
    public private(set) var phase: SubmitPhase = .idle
    @ObservationIgnored private var followUp: (() async throws -> Void)?
    @ObservationIgnored private var followUpFailure: (any Error) -> Void = { _ in }

    public init() {}

    public func run<T>(_ work: () async throws -> T, onFailure: @escaping (any Error) -> Void, afterSuccess: @escaping (T) async throws -> Void = { _ in }) async {
        guard !phase.busy else { return }
        phase = .loading
        do {
            let result = try await work()
            followUp = { try await afterSuccess(result) }
            followUpFailure = onFailure
            phase = .success
        } catch {
            onFailure(error)
            phase = .error
        }
    }

    /** 按钮画完勾：执行后续动作，按钮回到就绪。 */
    public func successShown() async {
        guard let next = followUp else { return }
        followUp = nil
        do {
            try await next()
            phase = .idle
        } catch {
            followUpFailure(error)
            phase = .error
        }
    }
}

/**
 * 表单底部的长按钮（完成 / 登录 / 注册 / 创建 / 发布）（Android `PulsoSubmitButton`）：
 * loading 时收缩成圆、里面转圈；success 画勾并向四周迸发粒子，然后调 [onSuccessShown]；error 抖一下重新展开。
 */
public struct PulsoSubmitButton: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let phase: SubmitPhase
    let action: () -> Void
    let onSuccessShown: () -> Void

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var tick: CGFloat = 0
    @State private var burst: CGFloat = 1
    @State private var shake: CGFloat = 0

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, phase: SubmitPhase, action: @escaping () -> Void, onSuccessShown: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.phase = phase
        self.action = action
        self.onSuccessShown = onSuccessShown
    }

    public var body: some View {
        let height = size.height
        GeometryReader { proxy in
            Button(action: action) {
                ZStack {
                    PulsoButtonLabel(title, systemImage: systemImage)
                        .opacity(phase.busy ? 0 : 1)
                    if phase == .loading {
                        ProgressView().tint(palette.onAccent)
                    }
                    if phase == .success {
                        TickShape()
                            .trim(from: 0, to: tick)
                            .stroke(palette.onAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.onAccent)
                // Shrinks into a circle the height of the button, then grows back.
                .frame(width: phase.busy ? height : proxy.size.width, height: height)
                .background {
                    if phase.busy {
                        Capsule(style: .continuous).fill(palette.accent.step(9))
                    } else {
                        palette.controlShape.fill(isEnabled ? palette.accent.step(9) : palette.text.opacity(0.12))
                    }
                }
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(phase.busy)
            .frame(maxWidth: .infinity)
            .overlay { ParticleBurst(progress: burst, color: palette.accent.step(9), baseRadius: height / 2) }
            .offset(x: shake)
            .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: phase.busy ? 0 : 0.25), value: phase.busy)
        }
        .frame(height: height)
        .sensoryFeedback(.success, trigger: phase == .success)
        .sensoryFeedback(.error, trigger: phase == .error)
        .task(id: phase) {
            switch phase {
            case .success:
                if !reduceMotion {
                    try? await Task.sleep(for: .milliseconds(280))
                    withAnimation(.easeOut(duration: 0.26)) { tick = 1 }
                    burst = 0
                    withAnimation(.easeOut(duration: 0.56)) { burst = 1 }
                    try? await Task.sleep(for: .milliseconds(700))
                } else {
                    tick = 1
                }
                onSuccessShown()
            case .error:
                tick = 0
                guard !reduceMotion else { return }
                for offset in [-6.0, 6, -4, 4, 0] {
                    withAnimation(.easeInOut(duration: 0.07)) { shake = offset }
                    try? await Task.sleep(for: .milliseconds(70))
                }
            case .idle, .loading:
                tick = 0
            }
        }
    }
}

/** 一个勾（可 trim 画出来）。 */
private struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.74))
        path.addLine(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.3))
        return path
    }
}

/**
 * 三圈错开的小粒子从中心飞出（[progress] 0 → 1，1 时不画）（Android `drawParticleBurst`）。点赞 / 收藏与提交成功共用。
 */
public struct ParticleBurst: View {
    let progress: CGFloat
    let color: Color
    let baseRadius: CGFloat

    public init(progress: CGFloat, color: Color, baseRadius: CGFloat) {
        self.progress = progress
        self.color = color
        self.baseRadius = baseRadius
    }

    public var body: some View {
        Canvas { context, size in
            guard progress < 1 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for ring in 0 ..< 3 {
                let delay = CGFloat(ring) * 0.12
                let local = min(1, max(0, (progress - delay) / (1 - delay)))
                guard local > 0, local < 1 else { continue }
                let eased = 1 - pow(1 - local, 3)
                let distance = baseRadius * (1 + (0.75 + 0.35 * CGFloat(ring)) * eased)
                let dot = baseRadius * 0.16 * (1 - local) * (1 - 0.2 * CGFloat(ring))
                for index in 0 ..< 8 {
                    let angle = 2 * .pi * (CGFloat(index) + CGFloat(ring) * 0.5) / 8
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(color.opacity(1 - local)))
                }
            }
        }
        .allowsHitTesting(false)
        .frame(width: baseRadius * 6, height: baseRadius * 6)
    }
}
