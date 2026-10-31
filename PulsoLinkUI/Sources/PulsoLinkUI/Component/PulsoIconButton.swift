import SwiftUI

/** 图标按钮变体（Android `PulsoIconButtonVariant`：按钮的四种 + 封面遮罩）。 */
public enum PulsoIconButtonVariant: Sendable {
    /** 封面上：半透明黑底 + 白图标。 */
    case overlay
    /** 强调色 step9 底 + 白图标。 */
    case solid
    /** step3 底 + step11 图标。 */
    case soft
    /** step8 描边 + step11 图标。 */
    case outline
}

/**
 * 统一图标按钮（Android `PulsoOverlayIconButton`）：封面 / 背景上用 [overlay]，头像角标等用 solid / soft / outline。
 * 形状跟主题 control（iOS 档是胶囊 / 圆），默认 32pt、图标 16pt。
 */
public struct PulsoIconButton: View {
    let systemImage: String
    let label: Text
    let variant: PulsoIconButtonVariant
    let tone: PulsoButtonTone
    let size: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ systemImage: String,
        label: Text,
        variant: PulsoIconButtonVariant = .overlay,
        tone: PulsoButtonTone = .accent,
        size: CGFloat = PulsoControlSize.small.height,
        iconSize: CGFloat = 16,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.variant = variant
        self.tone = tone
        self.size = size
        self.iconSize = iconSize
        self.action = action
    }

    public var body: some View {
        let scale = tone == .accent ? palette.accent : palette.gray
        let factor = isEnabled ? 1.0 : 0.45
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(foreground(scale).opacity(factor))
                .frame(width: size, height: size)
                .background(background(scale).opacity(variant == .soft && !isEnabled ? 0.55 : factor), in: palette.controlShape)
                .overlay {
                    if variant == .outline {
                        palette.controlShape.stroke(scale.step(8).opacity(factor), lineWidth: pulsoHairline)
                    }
                }
                .contentShape(palette.controlShape)
        }
        .buttonStyle(PulsoPressScaleStyle())
        .accessibilityLabel(label)
    }

    private func foreground(_ scale: RadixScale) -> Color {
        switch variant {
        case .overlay, .solid: .white
        case .soft, .outline: scale.step(11)
        }
    }

    private func background(_ scale: RadixScale) -> Color {
        switch variant {
        case .overlay: .black.opacity(0.36)
        case .solid: scale.step(9)
        case .soft: scale.step(3)
        case .outline: .clear
        }
    }
}

extension PulsoPalette {
    /** 头像：iOS 档是圆，其余 r4（Android `shapes.avatar`）。 */
    public var avatarShape: AnyShape {
        radius == .full ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: radius(4), style: .continuous))
    }
}
