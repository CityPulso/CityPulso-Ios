import SwiftUI

/**
 * 页面里的搜索框（Android `PulsoTextField` + 放大镜 leadingIcon）：control 形状细描边，聚焦时强调色描边；
 * 左边放大镜。高度跟页面控件档（默认 40）。
 */
public struct PulsoSearchField: View {
    @Binding var text: String
    let prompt: Text

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var size
    @FocusState private var focused: Bool

    public init(text: Binding<String>, prompt: Text) {
        _text = text
        self.prompt = prompt
    }

    public var body: some View {
        HStack(spacing: PulsoSpace.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryText)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(palette.secondaryText)) { prompt }
                .focused($focused)
                .submitLabel(.search)
                .foregroundStyle(palette.text)
                .tint(palette.accent.step(9))
        }
        .font(.body)
        .padding(.horizontal, PulsoSpace.s3)
        .frame(height: size.height)
        .overlay {
            palette.controlShape.stroke(focused ? palette.accent.step(9) : palette.outline, lineWidth: focused ? pulsoStrokeEmphasis : pulsoHairline)
        }
        .contentShape(palette.controlShape)
        .onTapGesture { focused = true }
    }
}
