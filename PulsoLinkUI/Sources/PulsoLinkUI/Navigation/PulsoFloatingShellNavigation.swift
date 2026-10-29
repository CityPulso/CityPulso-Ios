import PulsoLinkCore
import SwiftUI

/**
 * 悬浮底栏（对应 Android `PulsoFloatingShellNavigation`）：左边胶囊放槽 1–4 和「应用」，右边单独的圆形按钮放槽 6。
 * 材质用 iOS 26 系统 Liquid Glass（`glassEffect`），系统 TabView 在 iPhone 上最多 5 个 Tab，排不下这套布局。
 * 「应用」展开时，其余页面的格子在同一块玻璃里从底栏上方长出来。
 */
public struct PulsoFloatingShellNavigation: View {
    private static let barHeight: CGFloat = 62
    private static let gap: CGFloat = 10

    private let slots: [ResolvedAndroidNavSlot]
    private let action: ResolvedAndroidNavSlot
    private let trayDestinations: [ShellDestination]
    private let selection: ShellDestination
    @Binding private var appsExpanded: Bool
    private let onOpen: (ShellDestination) -> Void

    @Namespace private var glass
    @Namespace private var highlight

    public init(
        slots: [ResolvedAndroidNavSlot],
        action: ResolvedAndroidNavSlot,
        trayDestinations: [ShellDestination],
        selection: ShellDestination,
        appsExpanded: Binding<Bool>,
        onOpen: @escaping (ShellDestination) -> Void
    ) {
        self.slots = slots
        self.action = action
        self.trayDestinations = trayDestinations
        self.selection = selection
        _appsExpanded = appsExpanded
        self.onOpen = onOpen
    }

    public var body: some View {
        GlassEffectContainer(spacing: Self.gap) {
            VStack(spacing: Self.gap) {
                if appsExpanded {
                    tray
                        .glassEffect(.regular, in: .rect(cornerRadius: 28))
                        .glassEffectID("tray", in: glass)
                }
                HStack(spacing: Self.gap) {
                    capsule
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("capsule", in: glass)
                    actionButton
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("action", in: glass)
                }
            }
        }
        .padding(.horizontal, 20)
        .animation(.bouncy, value: appsExpanded)
        .animation(.snappy, value: selection)
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            ForEach(slots, id: \.destination) { slot in
                item(
                    label: slot.destination.labelKey,
                    systemImage: slot.iconPack.systemImage,
                    selected: !appsExpanded && slot.destination == selection
                ) {
                    onOpen(slot.destination)
                }
            }
            item(label: "home_nav_apps", systemImage: "square.grid.2x2", selected: appsExpanded) {
                appsExpanded.toggle()
            }
        }
        .padding(4)
        .frame(height: Self.barHeight)
    }

    private var actionButton: some View {
        let selected = !appsExpanded && action.destination == selection
        return Button {
            onOpen(action.destination)
        } label: {
            Image(systemName: action.iconPack.systemImage)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: Self.barHeight, height: Self.barHeight)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(action.destination.labelKey))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func item(
        label: LocalizedStringKey,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 26)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    Capsule()
                        .fill(.fill.tertiary)
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var tray: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
            ForEach(trayDestinations, id: \.self) { destination in
                Button {
                    onOpen(destination)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: destination.defaultIconPack.systemImage)
                            .symbolVariant(destination == selection ? .fill : .none)
                            .font(.system(size: 22, weight: .medium))
                            .frame(height: 28)
                        Text(destination.labelKey)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(destination == selection ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
    }
}
