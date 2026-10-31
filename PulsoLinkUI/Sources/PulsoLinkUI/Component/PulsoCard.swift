import SwiftUI

/**
 * 统一卡片（Android `PulsoCard`）：面板底色跟随 solid / translucent 档位，卡片圆角，默认不描边（靠底色区分）。
 * 需要强调时传 [border]（如选中态强调色描边）。点按用外层 `Button { } label: { PulsoCard { … } }.buttonStyle(.plain)`。
 */
public struct PulsoCard<Content: View>: View {
    let border: Color?
    let content: Content

    @Environment(\.pulsoPalette) private var palette

    public init(border: Color? = nil, @ViewBuilder content: () -> Content) {
        self.border = border
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.text)
            .background(palette.panel, in: palette.cardShape)
            .overlay {
                if let border {
                    palette.cardShape.strokeBorder(border, lineWidth: pulsoStrokeEmphasis)
                }
            }
            .contentShape(palette.cardShape)
    }
}

/**
 * 页面背景（Android `pulsoPageBackground`，同 WEB 外壳 `.content`）：页面底色上 22pt 点阵，
 * 从顶部中间向下、向两侧渐隐；右上角一团强调色光晕，左下角一团更淡的。
 */
public struct PulsoPageBackground: View {
    @Environment(\.pulsoPalette) private var palette

    public init() {}

    public var body: some View {
        Canvas { context, size in
            let (w, h) = (size.width, size.height)
            let spacing: CGFloat = 22
            let dot = palette.text.opacity(0.14)
            var dots = Path()
            var y = spacing / 2
            while y < h {
                var x = spacing / 2
                while x < w {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(dot))
            // 点阵渐隐：顶部中间 90% × 75% 的椭圆，30% 以内清楚，外面盖回页面底色。
            ellipse(&context, size, CGPoint(x: w / 2, y: 0), w * 0.9, h * 0.75,
                    [.init(color: .clear, location: 0.3), .init(color: palette.background, location: 1)])
            let accent = palette.accent.step(9)
            ellipse(&context, size, CGPoint(x: 0, y: h), w * 0.45, h * 0.35,
                    [.init(color: accent.opacity(0.05), location: 0), .init(color: .clear, location: 0.7)])
            ellipse(&context, size, CGPoint(x: w, y: 0), w * 0.55, h * 0.4,
                    [.init(color: accent.opacity(0.12), location: 0), .init(color: .clear, location: 0.7)])
        }
        .background(palette.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /** CSS `radial-gradient(ellipse rx ry at center, …)`：圆形渐变压成椭圆，最后一个色标铺满椭圆外。 */
    private func ellipse(_ context: inout GraphicsContext, _ size: CGSize, _ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ stops: [Gradient.Stop]) {
        guard rx > 0, ry > 0 else { return }
        var squashed = context
        let squash = ry / rx
        squashed.translateBy(x: center.x, y: center.y)
        squashed.scaleBy(x: 1, y: squash)
        squashed.translateBy(x: -center.x, y: -center.y)
        let cover = CGRect(x: 0, y: center.y - center.y / squash, width: size.width, height: size.height / squash)
        squashed.fill(Path(cover), with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: rx))
    }
}

extension View {
    /** 普通页面的底：点阵 + 强调色光晕，列表 / 表单的系统底色让出来。 */
    public func pulsoPageBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { PulsoPageBackground() }
    }
}
