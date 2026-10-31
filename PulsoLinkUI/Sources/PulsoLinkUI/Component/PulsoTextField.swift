import SwiftUI

/**
 * 统一输入框（Android `PulsoTextField` / `PulsoPasswordField`，M3 outlined）：
 * - 高度与 [PulsoButtonStyle] 同档；标签在框内，聚焦或有内容时浮到上边框，边框在标签处断开。
 * - 平时 0.5pt gray8 描边；聚焦 1pt 强调色；出错 1pt 红色，[errorText] 在框下一行。
 * - [hintText] 在框下一行说明用途（没有错误时显示）。
 * - [secure] 是密码框：右侧眼睛切换明文。
 */
public struct PulsoTextField: View {
    let label: Text
    @Binding var text: String
    let prompt: String?
    let hintText: String?
    let errorText: String?
    let secure: Bool
    let size: PulsoControlSize?

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var pageSize
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool
    @State private var revealed = false
    @State private var labelWidth: CGFloat = 0

    public init(
        _ label: LocalizedStringKey,
        text: Binding<String>,
        prompt: String? = nil,
        hintText: String? = nil,
        errorText: String? = nil,
        secure: Bool = false,
        size: PulsoControlSize? = nil
    ) {
        self.init(label: Text(label), text: text, prompt: prompt, hintText: hintText, errorText: errorText, secure: secure, size: size)
    }

    /** 标签已经是 `Text`（别的文案包里的字）。 */
    public init(
        label: Text,
        text: Binding<String>,
        prompt: String? = nil,
        hintText: String? = nil,
        errorText: String? = nil,
        secure: Bool = false,
        size: PulsoControlSize? = nil
    ) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.hintText = hintText
        self.errorText = errorText
        self.secure = secure
        self.size = size
    }

    private var floated: Bool { focused || !text.isEmpty }
    private var height: CGFloat { (size ?? pageSize).height }

    private var borderColor: Color {
        if errorText != nil { return palette.error }
        return focused ? palette.accent.step(9) : palette.outline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s1) {
            HStack(spacing: PulsoSpace.s2) {
                ZStack(alignment: .leading) {
                    if floated, text.isEmpty, let prompt {
                        Text(verbatim: prompt).foregroundStyle(palette.secondaryText)
                    }
                    field
                        .focused($focused)
                        .accessibilityLabel(label)
                        .foregroundStyle(isEnabled ? palette.text : palette.text.opacity(0.38))
                        .tint(palette.accent.step(9))
                }
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(palette.secondaryText)
                            .frame(width: PulsoControlSize.small.height, height: PulsoControlSize.small.height)
                    }
                    .buttonStyle(.plain)
                    // Android 同样写死英文（没有文案 key）。
                    .accessibilityLabel(Text(verbatim: revealed ? "Hide password" : "Show password"))
                }
            }
            .font(.body)
            .padding(.leading, PulsoSpace.s4)
            .padding(.trailing, secure ? PulsoSpace.s1 : PulsoSpace.s4)
            .frame(height: height)
            .background { outline }
            .overlay(alignment: .topLeading) { floatingLabel }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .animation(.easeOut(duration: 0.15), value: floated)

            if let supporting = errorText ?? hintText {
                Text(verbatim: supporting)
                    .font(.caption)
                    .foregroundStyle(errorText != nil ? palette.error : palette.secondaryText)
                    .padding(.leading, PulsoSpace.s3)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if secure, !revealed {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }

    /** 标签：没内容时就是占位字，聚焦或有内容时缩小浮到上边框。 */
    private var floatingLabel: some View {
        label
            .font(floated ? .caption : .body)
            .foregroundStyle(errorText != nil && floated ? palette.error : palette.secondaryText)
            .lineLimit(1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            .padding(.horizontal, floated ? PulsoSpace.s1 : 0)
            .offset(x: floated ? PulsoSpace.s3 : PulsoSpace.s4, y: floated ? -7 : (height - 22) / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /** 描边在浮起的标签处挖空（M3 outlined 的缺口）。 */
    private var outline: some View {
        palette.controlShape
            .stroke(borderColor, lineWidth: focused || errorText != nil ? pulsoStrokeEmphasis : pulsoHairline)
            .mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        if floated {
                            Rectangle()
                                .frame(width: labelWidth + PulsoSpace.s2, height: 4)
                                .offset(x: PulsoSpace.s3, y: -2)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
    }
}
