import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 预约页（Android `VenueBookScreen`）：顶部切换活动类型时原地换成那种类型的预约内容，不再压一层新页面；
 * 桌台类是时段表，密室 / 剧本杀是场次。
 */
struct VenueBookPage: View {
    let venueId: String
    @State private var activityType: VenueActivityType

    init(venueId: String, activityType: VenueActivityType) {
        self.venueId = venueId
        _activityType = State(initialValue: activityType)
    }

    var body: some View {
        Group {
            if activityType.isSessionVenue {
                SessionBookView(venueId: venueId, activityType: activityType) { activityType = $0 }
            } else {
                VenueBookView(venueId: venueId, activityType: activityType) { activityType = $0 }
            }
        }
        .id(activityType)
    }
}

extension VenueActivityType {
    /** 按场次订（密室、剧本杀），其余按桌台 / 包间 / 机位的时段订。 */
    var isSessionVenue: Bool { self == .escapeRoom || self == .scriptMurder }
}

/** 吸顶的活动类型切换（超过一种时）。 */
struct VenueBookActivityTypeBar: View {
    let activityTypes: [VenueActivityType]
    let selected: VenueActivityType
    let onSelect: (VenueActivityType) -> Void

    var body: some View {
        if activityTypes.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activityTypes, id: \.self) { activityType in
                        let isOn = activityType == selected
                        PulsoChoiceChip(Text(activityType.kind.labelKey), image: Image(activityType.kind.iconAsset), selected: isOn) {
                            onSelect(activityType)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/**
 * 选桌台（Android `SpaceBookPage`，按桌台订的类型共用）：日期条、桌台 × 时段表，底部是已选的几段、
 * 合计和「去确认」。日期和桌台列各自横向滚动，桌台多的门店也放得下。
 */
struct VenueBookView: View {
    let onSelectActivityType: (VenueActivityType) -> Void
    @State private var model: VenueBookModel
    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, activityType: VenueActivityType, onSelectActivityType: @escaping (VenueActivityType) -> Void) {
        self.onSelectActivityType = onSelectActivityType
        _model = State(initialValue: VenueBookModel(venueId: venueId, activityType: activityType))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.venue.data?.displayName ?? String(localized: "venue_book_title")))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let entry = model.entry.data {
                    SpaceSelectedBar(
                        lines: model.lines,
                        pricing: model.pricing,
                        timezone: entry.timezone,
                        currency: entry.currency,
                        dateLabel: model.dateKey.map { VenueTime.dateKeyLabel($0, locale: locale) } ?? "",
                        canContinue: model.canGoToConfirm,
                        upsellLevel: model.bestMemberLevel,
                        upsellSaveCents: model.memberSaveCents,
                        onRemove: { model.remove($0) },
                        onClear: { model.clearSelection() },
                        onContinue: {
                            if let route = model.confirmRoute { shell?.push(route) }
                        },
                        onOpenMembership: { shell?.push(NearRoute.venue(venueId: model.venueId, sheet: .membership)) }
                    )
                }
            }
            .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        if model.venue.isLoading, model.venue.data == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.venue.data == nil, let error = model.venue.error {
            if error.kind == .notFound {
                PulsoEmptyState(Text("venue_detail_not_found"), description: Text("venue_detail_not_found_body"))
            } else {
                PulsoLoadErrorView(error) { model.refresh() }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rulesAndBoard
                }
                .padding()
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
        }
    }

    /** 吸顶的活动类型切换和日期条（顶栏已经写了门店名）。 */
    private var header: some View {
        VStack(spacing: 8) {
            VenueBookActivityTypeBar(activityTypes: model.activityTypes, selected: model.activityType, onSelect: onSelectActivityType)
            SpaceDateStrip(dateKeys: model.dateKeys, selected: model.dateKey) { model.selectDate($0) }
        }
        .padding(.vertical, PulsoSpace.s2)
        .background(palette.gray.step(2))
    }

    @ViewBuilder
    private var rulesAndBoard: some View {
        if let entry = model.entry.data {
            if !model.isBookable {
                Text((entry.venueStatus != .published ? "venue_book_unpublished" : "venue_book_entry_unpublished") as LocalizedStringKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let board = model.board {
                if !board.bookable {
                    Text("venue_book_not_bookable").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    SpaceAvailabilityBoard(
                        day: board,
                        timezone: entry.timezone,
                        currency: entry.currency,
                        selection: model.selection,
                        onTap: { model.tap($0, $1) },
                        onPaint: { model.paint($0, $1) }
                    )
                }
            } else if let error = model.day.error {
                PulsoLoadErrorView(error) { model.refresh() }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            }
            if let error = model.selectionError {
                Text(verbatim: error).font(.footnote).foregroundStyle(.red)
            }
            Text(verbatim: localizedFormat(
                "venue_book_rules",
                String(entry.slotMinutes), String(entry.minBookingMinutes), String(entry.maxBookingMinutes), String(entry.bookingWindowDays)
            ))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        } else if let error = model.entry.error {
            PulsoLoadErrorView(error) { model.refresh() }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        }
    }
}

/** 日期条：日历图标 + 一排「星期 / 月日」小卡；选中的一天保持在视野里（Android `SpaceDateStrip`）。 */
struct SpaceDateStrip: View {
    let dateKeys: [String]
    let selected: String?
    let onSelect: (String) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        HStack(spacing: PulsoSpace.s2) {
            Image(systemName: "calendar").font(.title3).foregroundStyle(palette.secondaryText).accessibilityLabel(Text("venue_book_pick_date"))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if dateKeys.isEmpty {
                            ForEach(0 ..< 5, id: \.self) { _ in
                                palette.innerShape.fill(palette.gray.step(3)).frame(width: 56, height: 52)
                            }
                        }
                        ForEach(dateKeys, id: \.self) { key in
                            let parts = VenueTime.dateKeyParts(key, locale: locale)
                            let isOn = key == selected
                            Button { onSelect(key) } label: {
                                // 选中的日期是实心强调色块（Android 日期条）。
                                VStack(spacing: PulsoSpace.half) {
                                    Text(verbatim: parts.weekday).font(.subheadline.weight(isOn ? .bold : .medium))
                                    Text(verbatim: parts.day).font(.caption.monospacedDigit()).lineLimit(1)
                                }
                                .foregroundStyle(isOn ? palette.onAccent : palette.secondaryText)
                                .frame(width: 60)
                                .padding(.vertical, PulsoSpace.s2)
                                .background(isOn ? palette.accent.step(9) : Color.clear, in: palette.innerShape)
                            }
                            .buttonStyle(.plain)
                            .id(key)
                        }
                    }
                    .padding(.trailing)
                }
                .onChange(of: selected) {
                    if let selected { withAnimation { proxy.scrollTo(selected, anchor: .center) } }
                }
            }
        }
        .padding(.leading)
    }
}

/**
 * 选桌台页的底部栏（Android `SpaceSelectedBar`）：已选的几段（可以逐段移除）、合计（有效会员时原价划掉、下面是会员价），
 * 不是会员时提示成为会员能省多少，然后「去确认」。
 */
struct SpaceSelectedBar: View {
    let lines: [SpaceLineUi]
    let pricing: SpaceCheckoutPricing
    let timezone: String
    let currency: String
    let dateLabel: String
    let canContinue: Bool
    let upsellLevel: MembershipLevel?
    let upsellSaveCents: Int
    let onRemove: (SpaceLineUi) -> Void
    let onClear: () -> Void
    let onContinue: () -> Void
    let onOpenMembership: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if lines.isEmpty {
                Text("venue_book_pick_first").font(.subheadline).foregroundStyle(palette.secondaryText)
            } else {
                HStack {
                    Text(verbatim: localizedFormat("venue_book_selected_title", lines.count)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("venue_book_clear_all", action: onClear).font(.subheadline)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lines) { line in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: line.spaceName).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(verbatim: "\(dateLabel) \(VenueTime.clock(line.startsAt, timezone: timezone))–\(VenueTime.clock(line.endsAt, timezone: timezone))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Button { onRemove(line) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("venue_book_remove"))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: 200)
                            .background(palette.gray.step(3), in: palette.innerShape)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("venue_book_total").font(.subheadline)
                    Spacer()
                    PriceStack(listCents: pricing.totalListCents, payCents: pricing.totalPayCents, struck: pricing.struck, currency: currency, emphasized: true)
                }
                if let upsellLevel, upsellSaveCents > 0 {
                    MemberSaveHint(level: upsellLevel, amount: formatMoney(Double(upsellSaveCents) / 100, currency: currency, locale: locale), onTap: onOpenMembership)
                }
            }
            Button(action: onContinue) { Text("venue_book_goto_confirm") }
                .buttonStyle(.pulso(fullWidth: true))
                .environment(\.pulsoControlSize, .comfortable)
                .disabled(!canContinue)
        }
        .padding(PulsoSpace.s4)
        .background(palette.accent.step(2).shadow(.drop(color: .black.opacity(0.08), radius: 4, y: -1)))
    }
}

/** 有会员折扣时，原价划掉、下面是要付的（WEB checkout）。 */
struct PriceStack: View {
    let listCents: Int
    let payCents: Int
    let struck: Bool
    let currency: String
    var emphasized = false

    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if struck {
                Text(verbatim: formatMoney(Double(listCents) / 100, currency: currency, locale: locale))
                    .font(.caption.monospacedDigit())
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: formatMoney(Double(payCents) / 100, currency: currency, locale: locale))
                .font((emphasized ? Font.headline : Font.subheadline).monospacedDigit().weight(emphasized ? .bold : .medium))
                .foregroundStyle(struck ? palette.accent.step(11) : palette.text)
        }
    }
}

/** 「成为会员，本单最高省 …」：点开会员方案。 */
struct MemberSaveHint: View {
    let level: MembershipLevel
    let amount: String
    let onTap: () -> Void

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                MembershipLevelBadge(icon: level.icon, color: level.color, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: localizedFormat("venue_book_member_save", amount)).font(.subheadline.weight(.semibold))
                    Text(verbatim: localizedFormat("venue_book_member_save_level", level.name, bookingDiscountZhe(level.discountPercent), String(level.discountPercent)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(palette.accent.step(3), in: palette.innerShape)
        }
        .buttonStyle(.plain)
    }
}
