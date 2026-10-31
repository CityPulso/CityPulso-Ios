import SwiftUI

/** 按钮变体（Radix Button variant：solid / soft / outline / ghost；Android `PulsoButtonVariant`）。 */
public enum PulsoButtonVariant: Sendable {
    case solid
    case soft
    case outline
    /** 按下前没有底色：行内文字动作（「全部已读」、行尾动作）。 */
    case ghost
}

/** 按钮色调：默认强调色，可切灰（Radix Button `color`）。 */
public enum PulsoButtonTone: Sendable {
    case accent
    case gray
}

/**
 * 统一按钮样式（Android `PulsoButton`）：主题强调色配色、圆角档位定形状、高度与 [PulsoTextField] 同档。
 * 配色按 Radix step：solid = step9 底；soft = step3 底 + step11 字；outline = step8 边 + step11 字；ghost 只有 step11 字。
 * 不可用时同 M3：底 = 正文色 12%，字 = 正文色 38%。
 */
public struct PulsoButtonStyle: ButtonStyle {
    var variant: PulsoButtonVariant
    var tone: PulsoButtonTone
    var size: PulsoControlSize?
    var fullWidth: Bool

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var pageSize
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        let size = size ?? pageSize
        let scale = tone == .accent ? palette.accent : palette.gray
        configuration.label
            .font(size == .small ? .footnote.weight(.medium) : .subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .labelStyle(PulsoButtonLabelStyle())
            .foregroundStyle(isEnabled ? foreground(scale) : palette.text.opacity(0.38))
            // 加载圈跟随字色。
            .tint(isEnabled ? foreground(scale) : palette.text.opacity(0.38))
            .padding(.horizontal, size == .small ? PulsoSpace.s3 : PulsoSpace.s5)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .background {
                palette.controlShape
                    .fill(isEnabled ? fill(scale) : (variant == .ghost || variant == .outline ? .clear : palette.text.opacity(0.12)))
                    .overlay {
                        if variant == .outline {
                            palette.controlShape.stroke(isEnabled ? scale.step(8) : palette.text.opacity(0.12), lineWidth: pulsoHairline)
                        }
                    }
            }
            .overlay {
                if configuration.isPressed {
                    palette.controlShape.fill(foreground(scale).opacity(0.1))
                }
            }
            .contentShape(palette.controlShape)
    }

    private func foreground(_ scale: RadixScale) -> Color {
        switch variant {
        case .solid: tone == .accent ? palette.onAccent : .white
        case .soft, .outline, .ghost: scale.step(11)
        }
    }

    private func fill(_ scale: RadixScale) -> Color {
        switch variant {
        case .solid: scale.step(9)
        case .soft: scale.step(3)
        case .outline, .ghost: .clear
        }
    }
}

/** 按钮里的图标：16pt，和文字间距 4（Android icon2 + space1）。 */
private struct PulsoButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: PulsoSpace.s1) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == PulsoButtonStyle {
    /** [fullWidth] 撑满一行（表单底部的主按钮）。 */
    public static func pulso(
        _ variant: PulsoButtonVariant = .solid,
        tone: PulsoButtonTone = .accent,
        size: PulsoControlSize? = nil,
        fullWidth: Bool = false
    ) -> PulsoButtonStyle {
        PulsoButtonStyle(variant: variant, tone: tone, size: size, fullWidth: fullWidth)
    }
}

/** 按钮内容：加载中换成跟随字色的小转圈，按钮宽高不变。 */
public struct PulsoButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let loading: Bool

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, loading: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.loading = loading
    }

    public var body: some View {
        ZStack {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .opacity(loading ? 0 : 1)
            if loading {
                ProgressView().controlSize(.small)
            }
        }
    }
}
