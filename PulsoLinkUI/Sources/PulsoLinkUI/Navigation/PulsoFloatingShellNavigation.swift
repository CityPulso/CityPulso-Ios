import PulsoLinkCore
import SwiftUI

/**
 * 悬浮底栏（对应 Android `PulsoFloatingShellNavigation`）：左边胶囊放槽 1–4 和「应用」，右边单独的圆形按钮放槽 6。
 * 材质用 iOS 26 系统 Liquid Glass（`glassEffect`），系统 TabView 在 iPhone 上最多 5 个 Tab，排不下这套布局。
 * 「应用」展开时，其余页面的格子在同一块玻璃里从胶囊上方长出来（和胶囊同宽，标题「应用」）。
 * 底栏只放图标，选中项垫一块浅强调色圆；格子里的图标也在浅强调色圆里（Android 底栏 / 应用面板）。
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
    @Environment(\.pulsoPalette) private var palette

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
                    HStack(spacing: Self.gap) {
                        tray
                            .frame(maxWidth: .infinity)
                            .glassEffect(.regular, in: .rect(cornerRadius: 28))
                            .glassEffectID("tray", in: glass)
                        Color.clear.frame(width: Self.barHeight, height: 1)
                    }
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
                .foregroundStyle(selected ? palette.accent.step(9) : palette.text)
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
            Image(systemName: systemImage)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(selected ? palette.accent.step(9) : palette.text)
                .frame(width: 46, height: 46)
                .background {
                    if selected {
                        Circle()
                            .fill(palette.accent.step(3))
                            .matchedGeometryEffect(id: "highlight", in: highlight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s4) {
            Text("home_nav_apps").font(.subheadline).foregroundStyle(palette.secondaryText)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: PulsoSpace.s5) {
                ForEach(trayDestinations, id: \.self) { destination in
                    Button {
                        onOpen(destination)
                    } label: {
                        VStack(spacing: PulsoSpace.s2) {
                            Image(systemName: destination.defaultIconPack.systemImage)
                                .symbolVariant(destination == selection ? .fill : .none)
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(palette.accent.step(9))
                                .frame(width: 52, height: 52)
                                .background(palette.accent.step(3), in: Circle())
                            Text(destination.labelKey)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, PulsoSpace.s5)
        .padding(.horizontal, PulsoSpace.s4)
    }
}
