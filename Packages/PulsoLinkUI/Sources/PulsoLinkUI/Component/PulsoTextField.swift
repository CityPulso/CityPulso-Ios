import SwiftUI

/**
 * 统一输入框：标签在上、[errorText] 在下；边框平时 [pulsoHairline]（0.5），获得焦点或出错时 [pulsoStrokeEmphasis]（1）。
 * [secure] 为密码框，右侧眼睛按钮切换明文。
 */
public struct PulsoTextField: View {
    private let label: LocalizedStringKey
    private let bundle: Bundle?
    @Binding private var text: String
    private let placeholder: LocalizedStringKey?
    private let errorText: String?
    private let secure: Bool
    private let size: PulsoControlSize

    @Environment(\.pulsoTheme) private var theme
    @FocusState private var focused: Bool
    @State private var revealed = false

    public init(
        _ label: LocalizedStringKey,
        bundle: Bundle? = nil,
        text: Binding<String>,
        placeholder: LocalizedStringKey? = nil,
        errorText: String? = nil,
        secure: Bool = false,
        size: PulsoControlSize = .compact
    ) {
        self.label = label
        self.bundle = bundle
        _text = text
        self.placeholder = placeholder
        self.errorText = errorText
        self.secure = secure
        self.size = size
    }

    public var body: some View {
        let colors = theme.colors
        let hasError = errorText != nil
        VStack(alignment: .leading, spacing: theme.dimensions.space1) {
            Text(label, bundle: bundle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colors.onSurface)

            HStack(spacing: theme.dimensions.space2) {
                field
                    .focused($focused)
                    .foregroundStyle(colors.onSurface)
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.dimensions.space3)
            .frame(minHeight: theme.dimensions.controlHeight(size))
            .background(colors.surfaceContainerLowest, in: theme.shapes.control)
            .overlay {
                theme.shapes.control.stroke(
                    hasError ? colors.error : (focused ? colors.primary : colors.outline),
                    lineWidth: hasError || focused ? pulsoStrokeEmphasis : pulsoHairline
                )
            }
            .animation(.easeOut(duration: 0.15), value: focused)

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(colors.error)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = placeholder.map { Text($0, bundle: bundle).foregroundStyle(theme.colors.onSurfaceVariant) }
        if secure && !revealed {
            SecureField(text: $text, prompt: prompt) { Text(label, bundle: bundle) }
        } else {
            TextField(text: $text, prompt: prompt) { Text(label, bundle: bundle) }
        }
    }
}
