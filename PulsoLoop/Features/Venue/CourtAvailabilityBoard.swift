import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 场地 × 时段的可订表（Android `CourtAvailabilityBoard`，WEB `*AvailabilityBoard`，所有球场类运动共用）：行是所有场地
 * 时段开始时间的并集，列是场地。
 *
 * - 点一格：只切换那一格（两次点之间不会自动补满）。
 * - 长按后往任意方向拖：手指经过的空格都加上。
 * 可以选多块场地、每块场地多段。
 */
struct CourtAvailabilityBoard: View {
    let day: CourtDayUi
    let timezone: String
    let currency: String
    let selection: BoardSelection
    var enabled = true
    let onTap: (String, Int) -> Void
    let onPaint: (String, Int) -> Void

    private static let timeColumnWidth: CGFloat = 52
    private static let cellWidth: CGFloat = 76
    private static let cellHeight: CGFloat = 40
    private static let photoHeight: CGFloat = 44

    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette
    @State private var lastPainted: CellPosition?

    private struct CellPosition: Equatable {
        let column: Int
        let row: Int
    }

    private var rows: [String] {
        Array(Set(day.courts.flatMap { $0.slots.filter { $0.status != .unavailable }.map(\.startsAt) })).sorted()
    }

    private var headerHeight: CGFloat {
        Self.cellHeight
            + (day.courts.contains { $0.subtitle != nil } ? 12 : 0)
            + (day.courts.contains { $0.imageURL != nil } ? Self.photoHeight + 4 : 0)
    }

    var body: some View {
        let rows = rows
        if rows.isEmpty {
            Text("venue_board_closed_day").font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("venue_board_hint").font(.footnote).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(width: Self.timeColumnWidth, height: headerHeight)
                        ForEach(rows, id: \.self) { startsAt in
                            Text(verbatim: VenueTime.clock(startsAt, timezone: timezone))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: Self.timeColumnWidth, height: Self.cellHeight, alignment: .leading)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        columns(rows)
                            .coordinateSpace(.named("court-board"))
                            .gesture(paintGesture(rows), including: enabled ? .all : .none)
                    }
                }
                legend
            }
        }
    }

    private func columns(_ rows: [String]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(day.courts) { court in
                let indexes = Dictionary(court.slots.enumerated().map { ($0.element.startsAt, $0.offset) }, uniquingKeysWith: { first, _ in first })
                let picked = Set(selection[court.courtId] ?? [])
                VStack(spacing: 0) {
                    header(court)
                    ForEach(rows, id: \.self) { startsAt in
                        let index = indexes[startsAt]
                        let slot = index.map { court.slots[$0] }
                        let kind = CellKind(slot, selected: index.map(picked.contains) ?? false)
                        cell(kind, slot: slot)
                            .contentShape(.rect)
                            .onTapGesture {
                                guard enabled, let index else { return }
                                onTap(court.courtId, index)
                            }
                    }
                }
            }
        }
    }

    private func header(_ court: CourtColumnUi) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: court.name).font(.caption.weight(.semibold)).lineLimit(1)
            if let subtitle = court.subtitle {
                Text(verbatim: subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let imageURL = court.imageURL {
                PulsoRemoteImage(url: imageURL)
                    .frame(height: Self.photoHeight)
                    .clipShape(palette.innerShape)
            }
        }
        .padding(.horizontal, 2)
        .frame(width: Self.cellWidth, height: headerHeight)
    }

    private func cell(_ kind: CellKind, slot: CourtSlotUi?) -> some View {
        let label: String? = switch kind {
        case .available: slot?.priceCents.map { formatMoney(Double($0) / 100, currency: currency, locale: locale) }
        case .selected: nil
        case .taken, .blocked: slot.flatMap(occupancyLabel) ?? String(localized: "venue_board_legend_taken")
        case .closed: "—"
        }
        return ZStack {
            palette.innerShape.fill(kind.fill(palette))
            if kind == .selected {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(palette.onAccent)
            } else if let label {
                Text(verbatim: label).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(kind.foreground(palette)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(2)
        .frame(width: Self.cellWidth, height: Self.cellHeight)
    }

    /** 课程 / 赛事 / 私教占的格子显示名字，订场的人知道那时在干什么。 */
    private func occupancyLabel(_ slot: CourtSlotUi) -> String? {
        if let title = slot.title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        switch slot.occupancy {
        case .course: return String(localized: "venue_board_occupancy_course")
        case .tournament: return String(localized: "venue_board_occupancy_tournament")
        case .coaching: return String(localized: "venue_board_occupancy_coaching")
        default: return nil
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([CellKind.available, .selected, .taken, .blocked], id: \.self) { kind in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(kind.fill(palette)).frame(width: 12, height: 12)
                    Text(kind.legendKey).font(.caption2).foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    /* ------------------------------ 长按拖动连选 ------------------------------ */

    private func paintGesture(_ rows: [String]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("court-board")))
            .onChanged { value in
                guard case let .second(true, drag) = value, let drag else { return }
                guard let cell = cellAt(drag.location, rows: rows) else { return }
                let from = lastPainted ?? cell
                for position in coverLine(from, cell) { paint(position, rows: rows) }
                lastPainted = cell
            }
            .onEnded { _ in lastPainted = nil }
    }

    private func cellAt(_ point: CGPoint, rows: [String]) -> CellPosition? {
        guard point.y >= headerHeight else { return nil }
        let column = Int(point.x / Self.cellWidth)
        let row = Int((point.y - headerHeight) / Self.cellHeight)
        guard day.courts.indices.contains(column), rows.indices.contains(row) else { return nil }
        return CellPosition(column: column, row: row)
    }

    private func paint(_ position: CellPosition, rows: [String]) {
        let court = day.courts[position.column]
        guard let index = court.slots.firstIndex(where: { $0.startsAt == rows[position.row] }) else { return }
        onPaint(court.courtId, index)
    }

    /** 直线拖过的格子，两端都算（WEB `coverLine`）；斜着走一步也经过拐角，两次采样之间不会漏格。 */
    private func coverLine(_ from: CellPosition, _ to: CellPosition) -> [CellPosition] {
        var cells = [from]
        let dx = to.column - from.column
        let dy = to.row - from.row
        let nx = abs(dx)
        let ny = abs(dy)
        let sx = dx.signum()
        let sy = dy.signum()
        var column = from.column
        var row = from.row
        var ix = 0
        var iy = 0
        while ix < nx || iy < ny {
            let decision = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
            if decision == 0 {
                column += sx; ix += 1; cells.append(CellPosition(column: column, row: row))
                row += sy; iy += 1; cells.append(CellPosition(column: column, row: row))
            } else if decision < 0 {
                column += sx; ix += 1; cells.append(CellPosition(column: column, row: row))
            } else {
                row += sy; iy += 1; cells.append(CellPosition(column: column, row: row))
            }
        }
        return cells
    }
}

private enum CellKind: Hashable {
    case available
    case selected
    case taken
    case blocked
    case closed

    init(_ slot: CourtSlotUi?, selected: Bool) {
        guard let slot, slot.status != .unavailable else {
            self = .closed
            return
        }
        if selected {
            self = .selected
        } else if slot.isOpen {
            self = .available
        } else if slot.status == .booked || slot.status == .held {
            self = .taken
        } else if slot.status == .blocked {
            self = .blocked
        } else {
            self = .closed
        }
    }

    /** 可订是浅强调色底、强调色价格，已选是实心强调色（Android 选场表）。 */
    func fill(_ palette: PulsoPalette) -> Color {
        switch self {
        case .available: palette.accent.step(3)
        case .selected: palette.accent.step(9)
        case .taken: palette.gray.step(3)
        case .blocked: Color.orange.opacity(0.15)
        case .closed: Color.clear
        }
    }

    func foreground(_ palette: PulsoPalette) -> Color {
        switch self {
        case .available: palette.accent.step(11)
        case .selected: palette.onAccent
        case .taken, .blocked, .closed: palette.secondaryText
        }
    }

    var legendKey: LocalizedStringKey {
        switch self {
        case .available: "venue_board_legend_available"
        case .selected: "venue_board_legend_selected"
        case .taken: "venue_board_legend_taken"
        case .blocked: "venue_board_legend_blocked"
        case .closed: "venue_board_closed_day"
        }
    }
}
