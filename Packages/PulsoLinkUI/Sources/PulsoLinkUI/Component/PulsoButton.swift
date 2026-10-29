import SwiftUI

/** 按钮变体（与 Radix Button variant 对齐：solid / soft / outline / ghost）。 */
public enum PulsoButtonVariant: Sendable {
    case solid
    case soft
    case outline
    /** 按下前没有底色：行内文字操作（列表行操作、「全部已读」）。 */
    case ghost
}

/** 按钮色调（与 Radix Button `color` prop 对齐：默认 accent，可切 gray）。 */
public enum PulsoButtonTone: Sendable {
    case accent
    case gray
}

/**
 * 统一按钮：主题 accent 驱动配色，radius 档位驱动形状，[size] 驱动高度（与 [PulsoTextField] 同档同高）；
 * loading 时禁用并显示进度圈。[systemImage] 是跟随按钮字色的 SF Symbol。
 */
public struct PulsoButton: View {
    private let title: LocalizedStringKey
    private let bundle: Bundle?
    private let systemImage: String?
    private let variant: PulsoButtonVariant
    private let tone: PulsoButtonTone
    private let size: PulsoControlSize
    private let loading: Bool
    private let action: () -> Void

    @Environment(\.pulsoTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: LocalizedStringKey,
        bundle: Bundle? = nil,
        systemImage: String? = nil,
        variant: PulsoButtonVariant = .solid,
        tone: PulsoButtonTone = .accent,
        size: PulsoControlSize = .compact,
        loading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.bundle = bundle
        self.systemImage = systemImage
        self.variant = variant
        self.tone = tone
        self.size = size
        self.loading = loading
        self.action = action
    }

    public var body: some View {
        let scale = tone == .accent ? theme.colors.accent : theme.colors.gray
        let colors = palette(scale)
        Button(action: action) {
            ZStack {
                if loading {
                    ProgressView().tint(colors.foreground)
                } else {
                    HStack(spacing: theme.dimensions.space1) {
                        if let systemImage {
                            Image(systemName: systemImage).font(.system(size: theme.dimensions.icon2 * 0.9))
                        }
                        // 高度固定：长文案保持一行，先缩字再省略
                        Text(title, bundle: bundle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, theme.dimensions.space4)
            .frame(maxWidth: .infinity, minHeight: theme.dimensions.controlHeight(size))
            .background(colors.background, in: theme.shapes.control)
            .overlay {
                if variant == .outline {
                    theme.shapes.control.stroke(scale.step(8), lineWidth: pulsoHairline)
                }
            }
            .contentShape(theme.shapes.control)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    // Radix step 语义：solid=step9 底 / soft=step3 底 + step11 字 / outline=step8 边 + step11 字
    private func palette(_ scale: RadixScale) -> (background: Color, foreground: Color) {
        switch variant {
        case .solid: (scale.step(9), tone == .accent ? theme.colors.onPrimary : .white)
        case .soft: (scale.step(3), scale.step(11))
        case .outline, .ghost: (.clear, scale.step(11))
        }
    }
}
