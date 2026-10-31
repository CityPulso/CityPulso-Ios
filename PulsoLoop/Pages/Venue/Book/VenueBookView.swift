import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选场页（Android `CourtBookPage`，所有球场类运动共用）：运动切换、日期条、场地 × 时段表，底部是已选的几段、
 * 合计和「去确认」。运动、日期和场地列各自横向滚动，场地多、运动多的球馆也放得下。
 */
struct VenueBookView: View {
    @State private var model: VenueBookModel
    @Environment(\.locale) private var locale
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, sport: VenueSport) {
        _model = State(initialValue: VenueBookModel(venueId: venueId, sport: sport))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.venue.data?.displayName ?? String(localized: "venue_book_title")))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let entry = model.entry.data {
                    CourtSelectedBar(
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
                        onOpenMembership: { shell?.push(LoopRoute.venue(venueId: model.venueId, sheet: .membership)) }
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
                ContentUnavailableView {
                    Label("venue_detail_not_found", systemImage: "building.2")
                } description: {
                    Text("venue_detail_not_found_body")
                }
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

    /** 吸顶的运动切换和日期条（顶栏已经写了球馆名）。 */
    private var header: some View {
        VStack(spacing: 8) {
            if model.sports.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.sports, id: \.self) { sport in
                            Button { model.selectSport(sport) } label: {
                                HStack(spacing: 6) {
                                    Image(sport.loopSport.iconAsset).resizable().scaledToFit().frame(width: 18, height: 18)
                                    Text(sport.loopSport.labelKey).font(.subheadline.weight(sport == model.sport ? .semibold : .regular))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .foregroundStyle(sport == model.sport ? Color.white : Color.primary)
                                .background(sport == model.sport ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            CourtDateStrip(dateKeys: model.dateKeys, selected: model.dateKey) { model.selectDate($0) }
        }
        .padding(.vertical, 8)
        .background(.bar)
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
                    CourtAvailabilityBoard(
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

/** 日期条：日历图标 + 一排「星期 / 月日」小卡；选中的一天保持在视野里（Android `CourtDateStrip`）。 */
struct CourtDateStrip: View {
    let dateKeys: [String]
    let selected: String?
    let onSelect: (String) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").foregroundStyle(.secondary).accessibilityLabel(Text("venue_book_pick_date"))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if dateKeys.isEmpty {
                            ForEach(0 ..< 5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)).frame(width: 56, height: 44)
                            }
                        }
                        ForEach(dateKeys, id: \.self) { key in
                            let parts = VenueTime.dateKeyParts(key, locale: locale)
                            let isOn = key == selected
                            Button { onSelect(key) } label: {
                                VStack(spacing: 0) {
                                    Text(verbatim: parts.weekday).font(.caption.weight(.medium))
                                    Text(verbatim: parts.day).font(.caption2.monospacedDigit()).lineLimit(1)
                                }
                                .foregroundStyle(isOn ? Color.white : Color.secondary)
                                .frame(width: 56)
                                .padding(.vertical, 8)
                                .background(isOn ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 10))
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
 * 选场页的底部栏（Android `CourtSelectedBar`）：已选的几段（可以逐段移除）、合计（有效会员时原价划掉、下面是会员价），
 * 不是会员时提示成为会员能省多少，然后「去确认」。
 */
struct CourtSelectedBar: View {
    let lines: [CourtLineUi]
    let pricing: CourtCheckoutPricing
    let timezone: String
    let currency: String
    let dateLabel: String
    let canContinue: Bool
    let upsellLevel: MembershipLevel?
    let upsellSaveCents: Int
    let onRemove: (CourtLineUi) -> Void
    let onClear: () -> Void
    let onContinue: () -> Void
    let onOpenMembership: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if lines.isEmpty {
                Text("venue_book_pick_first").font(.subheadline).foregroundStyle(.secondary)
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
                                    Text(verbatim: line.courtName).font(.caption.weight(.semibold)).lineLimit(1)
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
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
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
            Button(action: onContinue) { Text("venue_book_goto_confirm").frame(maxWidth: .infinity) }
                .buttonStyle(.pulso())
                .controlSize(.large)
                .disabled(!canContinue)
        }
        .padding(16)
        .background(.bar)
    }
}

/** 有折扣或用时长包时，原价划掉、下面是要付的（WEB checkout）。 */
struct PriceStack: View {
    let listCents: Int
    let payCents: Int
    let struck: Bool
    let currency: String
    var emphasized = false

    @Environment(\.locale) private var locale

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
                .foregroundStyle(struck ? Color.accentColor : Color.primary)
        }
    }
}

/** 「成为会员，本单最高省 …」：点开会员方案。 */
struct MemberSaveHint: View {
    let level: MembershipLevel
    let amount: String
    let onTap: () -> Void

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
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
