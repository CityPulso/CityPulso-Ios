import SwiftUI

/**
 * 按压回弹（Android `pulsoPressBounce`）：按下缩到 [pressedScale]（默认 96%），松手先弹过头到 [overshoot]（默认 103%）再回到 100%。
 * Plain button look (the label draws itself), for filter buttons and chips.
 */
public struct PulsoPressBounceStyle: ButtonStyle {
    var pressedScale: CGFloat
    var overshoot: CGFloat

    public func makeBody(configuration: Configuration) -> some View {
        PressBounceBody(configuration: configuration, pressedScale: pressedScale, overshoot: overshoot)
    }
}

private struct PressBounceBody: View {
    let configuration: ButtonStyleConfiguration
    let pressedScale: CGFloat
    let overshoot: CGFloat
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(scale)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard !reduceMotion else { return }
                if pressed {
                    withAnimation(.easeOut(duration: 0.09)) { scale = pressedScale }
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { scale = overshoot } completion: {
                        withAnimation(.spring(duration: 0.3, bounce: 0.45)) { scale = 1 }
                    }
                }
            }
    }
}

extension ButtonStyle where Self == PulsoPressBounceStyle {
    public static var pulsoPressBounce: PulsoPressBounceStyle { PulsoPressBounceStyle(pressedScale: 0.96, overshoot: 1.03) }

    public static func pulsoPressBounce(pressedScale: CGFloat = 0.96, overshoot: CGFloat = 1.03) -> PulsoPressBounceStyle {
        PulsoPressBounceStyle(pressedScale: pressedScale, overshoot: overshoot)
    }
}

/**
 * 点赞 / 收藏成功（Android `pulsoToggleBurst`）：[active] 变成 true 时图标放大回弹，四周三圈小粒子迸发；取消只轻轻一缩。首次出现不动。
 */
private struct ToggleBurst: ViewModifier {
    let active: Bool
    let color: Color
    @State private var burst: CGFloat = 1
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .background {
                GeometryReader { proxy in
                    ParticleBurst(progress: burst, color: color, baseRadius: min(proxy.size.width, proxy.size.height) / 2)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: active)
            .onChange(of: active) { _, on in
                guard !reduceMotion else { return }
                if on {
                    burst = 0
                    withAnimation(.easeOut(duration: 0.56)) { burst = 1 }
                }
                withAnimation(.easeOut(duration: on ? 0.11 : 0.09)) { scale = on ? 1.3 : 0.85 } completion: {
                    withAnimation(.spring(duration: 0.35, bounce: 0.5)) { scale = 1 }
                }
            }
    }
}

extension View {
    public func pulsoToggleBurst(active: Bool, color: Color) -> some View {
        modifier(ToggleBurst(active: active, color: color))
    }
}
