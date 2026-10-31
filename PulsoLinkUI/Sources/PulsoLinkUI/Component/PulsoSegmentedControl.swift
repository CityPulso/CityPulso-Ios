import SwiftUI

/**
 * 分段选择（Android `PulsoSegmentedControl`，Radix SegmentedControl size 2）：高度与按钮 / 输入框同档；
 * 轨道 gray2 底 + 细边，选中是一块页面底色的滑块从旧格滑到新格，选中字半粗、其余次要字色。
 * 格子等分一行；字太长时缩小一点再省略。
 */
public struct PulsoSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Text

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var size
    @Namespace private var thumb

    public init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> Text) {
        self.options = options
        _selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button {
                    guard !active else { return }
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { selection = option }
                } label: {
                    label(option)
                        .font(.subheadline.weight(active ? .semibold : .regular))
                        .foregroundStyle(active ? palette.text : palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, PulsoSpace.s1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if active {
                                palette.segmentThumbShape
                                    .fill(palette.background)
                                    .overlay { palette.segmentThumbShape.stroke(palette.outlineVariant, lineWidth: pulsoHairline) }
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(palette.segmentThumbShape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(2)
        .frame(height: size.height)
        .background(palette.gray.step(2), in: palette.controlShape)
        .overlay { palette.controlShape.stroke(palette.outlineVariant, lineWidth: pulsoHairline) }
        .clipShape(palette.controlShape)
    }
}

extension PulsoPalette {
    /** 分段滑块：在 control 轨道内缩 2pt，full 档是胶囊、其余 r2。 */
    public var segmentThumbShape: AnyShape {
        radius == .full ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: radius(2), style: .continuous))
    }
}
