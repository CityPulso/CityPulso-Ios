import SwiftUI

/** 带文字的复选行：整行可点（含文字）。 */
public struct PulsoCheckbox: View {
    @Binding private var isOn: Bool
    private let label: LocalizedStringKey
    private let bundle: Bundle?

    @Environment(\.pulsoTheme) private var theme

    public init(_ label: LocalizedStringKey, bundle: Bundle? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.bundle = bundle
        _isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: theme.dimensions.space2) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: theme.dimensions.icon4 * 0.85))
                    .foregroundStyle(isOn ? theme.colors.primary : theme.colors.outline)
                    .contentTransition(.symbolEffect(.replace))
                Text(label, bundle: bundle)
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.onSurface)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
