import SwiftUI

/**
 * 极光式动态背景（Android `PulsoAuroraBackground`，欢迎 / 登录 / 注册 / 身份选择共用）：
 * 主题底色垫底，三团强调色径向光斑按 18s / 26s 周期缓慢漂移、9s 呼吸缩放。
 * 浅色用 step6 / step9 / step4 @ 0.75，深色压到 0.35，保证前景字对比度。
 * [breathingCircles]：再画几圈呼吸圆环和从右上扩散的涟漪（身份选择页）。
 */
public struct PulsoAuroraBackground: View {
    let breathingCircles: Bool

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(breathingCircles: Bool = false) {
        self.breathingCircles = breathingCircles
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, time: reduceMotion ? 0 : t)
            }
        }
        .background(palette.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let (w, h) = (size.width, size.height)
        let base = max(w, h)
        let phase1 = t.truncatingRemainder(dividingBy: 18) / 18 * 2 * .pi
        let phase2 = t.truncatingRemainder(dividingBy: 26) / 26 * 2 * .pi
        let breath = 1 + 0.1 * sin(t / 9 * .pi)
        let blobAlpha = colorScheme == .dark ? 0.35 : 0.75

        blob(&context, palette.accent.step(6).opacity(blobAlpha),
             CGPoint(x: w * (0.18 + 0.10 * sin(phase1)), y: h * (0.12 + 0.06 * cos(phase1))), base * 0.42 * breath)
        blob(&context, palette.accent.step(9).opacity(blobAlpha * 0.45),
             CGPoint(x: w * (0.88 - 0.12 * cos(phase2)), y: h * (0.38 + 0.10 * sin(phase2))), base * 0.34 * breath)
        blob(&context, palette.accent.step(4).opacity(blobAlpha),
             CGPoint(x: w * (0.30 + 0.14 * sin(phase2 + 1.6)), y: h * (0.92 - 0.06 * cos(phase1 + 0.8))), base * 0.46 * breath)

        guard breathingCircles else { return }
        let strokeAlpha = colorScheme == .dark ? 0.55 : 0.7
        let ringAlpha = 0.3 + 0.12 * sin(t / 4.2 * .pi)
        let ringA = 1 + 0.14 * sin(t / 4.2 * .pi)
        let ringB = 1 - 0.1 * sin(t / 5.6 * .pi)
        let ringC = 1 + 0.08 * sin(t / 3.8 * .pi)

        let c1 = CGPoint(x: w * 0.12, y: h * 0.18)
        ring(&context, palette.accent.step(8).opacity(ringAlpha * strokeAlpha), c1, base * 0.22 * ringA, 1.6)
        ring(&context, palette.accent.step(6).opacity(ringAlpha * 0.55 * strokeAlpha), c1, base * 0.14 * ringA, 1.2)
        let c2 = CGPoint(x: w * 0.92, y: h * 0.42)
        ring(&context, palette.accent.step(9).opacity(ringAlpha * 0.85 * strokeAlpha), c2, base * 0.18 * ringB, 1.6)
        blob(&context, palette.accent.step(6).opacity(blobAlpha * 0.28 * ringB), c2, base * 0.08 * ringB)
        ring(&context, palette.accent.step(7).opacity(ringAlpha * 0.7 * strokeAlpha), CGPoint(x: w * 0.22, y: h * 0.78), base * 0.12 * ringC, 1.2)

        let ripple = t.truncatingRemainder(dividingBy: 5.2) / 5.2
        for i in 0 ..< 2 {
            let p = (ripple + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            ring(&context, palette.accent.step(8).opacity((1 - p) * 0.32 * strokeAlpha),
                 CGPoint(x: w * 0.78, y: h * 0.14), base * (0.06 + p * 0.28), 1.2)
        }
    }

    private func blob(_ context: inout GraphicsContext, _ color: Color, _ center: CGPoint, _ radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: center, startRadius: 0, endRadius: radius)
        )
    }

    private func ring(_ context: inout GraphicsContext, _ color: Color, _ center: CGPoint, _ radius: CGFloat, _ width: CGFloat) {
        guard radius > 0 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)
    }
}
