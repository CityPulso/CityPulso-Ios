import SwiftUI

/**
 * 带文字的复选行（Android `PulsoCheckbox`，M3 Checkbox）：整行可点；选中是强调色实心小方块 + 白勾，
 * 未选中是 2pt 次要字色描边的空方块。
 */
public struct PulsoCheckbox: View {
    @Binding var isOn: Bool
    let label: Text

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(_ label: Text, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    public var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: PulsoSpace.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isOn ? palette.accent.step(9) : .clear)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(isOn ? palette.accent.step(9) : palette.secondaryText, lineWidth: 2)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .frame(width: 18, height: 18)
                .padding(PulsoSpace.s1)
                label
                    .font(.subheadline)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
