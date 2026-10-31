import SwiftUI

/**
 * 时间线逐段点亮（Android `rememberPulsoTimelineLit`）：列表停稳后，从上往下每 90ms 点亮一段，
 * 一直到离列表中线最近的那一行；再滚动就熄灭。行用 [pulsoTimelineRow] 登记，列表用 [pulsoTimelineList] 汇报滚动阶段和位置。
 */
@MainActor
@Observable
public final class PulsoTimelineTracker {
    /** 已点亮的行数（按 [order] 的顺序）。 */
    public private(set) var lit = 0
    public var order: [AnyHashable] = []
    @ObservationIgnored private var centers: [AnyHashable: CGFloat] = [:]
    @ObservationIgnored private var listMiddle: CGFloat = 0
    @ObservationIgnored private var lighting: Task<Void, Never>?

    public init() {}

    func record(_ id: AnyHashable, center: CGFloat) { centers[id] = center }
    func recordList(middle: CGFloat) { listMiddle = middle }

    func scrolling(_ moving: Bool, reduceMotion: Bool) {
        lighting?.cancel()
        guard !moving else {
            lit = 0
            return
        }
        let target = (order.enumerated()
            .compactMap { index, id in centers[id].map { (index, abs($0 - listMiddle)) } }
            .min { $0.1 < $1.1 }?.0).map { $0 + 1 } ?? 0
        if reduceMotion {
            lit = target
            return
        }
        lit = 0
        lighting = Task {
            while lit < target, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeOut(duration: 0.18)) { lit += 1 }
            }
        }
    }

    public func isLit(_ id: AnyHashable) -> Bool {
        guard let index = order.firstIndex(of: id) else { return false }
        return index < lit
    }
}

private struct TimelineRow: ViewModifier {
    let id: AnyHashable
    let tracker: PulsoTimelineTracker
    @Environment(\.pulsoPalette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(.leading, PulsoSpace.s3)
            .overlay(alignment: .leading) {
                // The segment beside the row: grey, accent once lit.
                Capsule()
                    .fill(tracker.isLit(id) ? palette.accent.step(9) : palette.outlineVariant)
                    .frame(width: 2)
                    .padding(.vertical, -PulsoSpace.s2)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { tracker.record(id, center: $0) }
    }
}

private struct TimelineList: ViewModifier {
    let tracker: PulsoTimelineTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { tracker.recordList(middle: $0) }
            .onScrollPhaseChange { _, phase in tracker.scrolling(phase != .idle, reduceMotion: reduceMotion) }
    }
}

extension View {
    /** 一行带一段时间线；[id] 要出现在 tracker 的 `order` 里。 */
    public func pulsoTimelineRow(_ id: some Hashable, tracker: PulsoTimelineTracker) -> some View {
        modifier(TimelineRow(id: AnyHashable(id), tracker: tracker))
    }

    /** 放在列表上：停稳时点亮时间线。 */
    public func pulsoTimelineList(_ tracker: PulsoTimelineTracker) -> some View {
        modifier(TimelineList(tracker: tracker))
    }
}
