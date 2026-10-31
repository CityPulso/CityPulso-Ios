import SwiftUI

/**
 * 卡片堆叠（Android `PulsoCardStack`）：收起时第一张在最上，后面 [peekCards] − 1 张从下边露出一截、逐张变小；点一下调 [onExpand]。
 * 展开（[expanded]）时逐张错开时间弹开成一列，收回时倒序叠回。卡片自己的点击只在展开后生效。
 */
public struct PulsoCardStack<Item, ID: Hashable, Card: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let expanded: Bool
    let onExpand: () -> Void
    let peekCards: Int
    let card: (Item) -> Card

    @State private var opened: Set<ID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [Item], id: KeyPath<Item, ID>, expanded: Bool, peekCards: Int = 3, onExpand: @escaping () -> Void, @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.id = id
        self.expanded = expanded
        self.peekCards = peekCards
        self.onExpand = onExpand
        self.card = card
    }

    public var body: some View {
        DeckLayout(peek: 14, spacing: PulsoSpace.s3, peekCards: peekCards) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let open = opened.contains(item[keyPath: id])
                let depth = CGFloat(min(index, peekCards - 1))
                card(item)
                    .scaleEffect(open ? 1 : 1 - depth * 0.05, anchor: .bottom)
                    .opacity(open || index < peekCards ? 1 : 0)
                    .zIndex(Double(items.count - index))
                    .layoutValue(key: CardOpen.self, value: open)
                    .allowsHitTesting(expanded)
            }
        }
        .overlay {
            if !expanded, !items.isEmpty {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onExpand)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("pulso_ui_stack_expand", bundle: .module))
            }
        }
        .onAppear { if expanded { opened = Set(items.map { $0[keyPath: id] }) } }
        .task(id: expanded) {
            // Open one after another from the top; close in reverse order.
            let order = expanded ? items : items.reversed()
            for item in order {
                if reduceMotion {
                    if expanded { opened.insert(item[keyPath: id]) } else { opened.remove(item[keyPath: id]) }
                    continue
                }
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                    if expanded { opened.insert(item[keyPath: id]) } else { opened.remove(item[keyPath: id]) }
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}

private struct CardOpen: LayoutValueKey {
    static let defaultValue = false
}

/** Closed cards lie on the first one, peeking out below it; open cards stack into a column. */
private struct DeckLayout: Layout {
    let peek: CGFloat
    let spacing: CGFloat
    let peekCards: Int

    private func positions(_ subviews: Subviews, width: CGFloat?) -> (ys: [CGFloat], heights: [CGFloat]) {
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let first = heights.first ?? 0
        var openY: CGFloat = 0
        var ys: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let stacked = CGFloat(min(index, peekCards - 1)) * peek + max(0, first - heights[index])
            ys.append(subview[CardOpen.self] ? openY : stacked)
            openY += heights[index] + spacing
        }
        return (ys, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (ys, heights) = positions(subviews, width: proposal.width)
        let height = zip(ys, heights).map { $0 + $1 }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (ys, _) = positions(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + ys[index]), proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/** 顶栏上展开 / 收起卡片堆的按钮（Android `PulsoStackToggleAction`），图标切换时淡入缩放。 */
public struct PulsoStackToggleButton: View {
    @Binding var expanded: Bool

    public init(expanded: Binding<Bool>) {
        _expanded = expanded
    }

    public var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "chevron.up.chevron.down")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(Text(expanded ? "pulso_ui_stack_collapse" : "pulso_ui_stack_expand", bundle: .module))
    }
}
