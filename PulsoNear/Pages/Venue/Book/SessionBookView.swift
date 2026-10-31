import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选场次（Android `SessionBookPage`，密室和剧本杀共用，WEB `EscapeRoomBookPanel`）：吸顶的活动类型切换和日期条，
 * 每个主题 / 剧本一张卡片列出当天的开始时间；底部是选中的一场、人数、价格和「去确认」。
 */
struct SessionBookView: View {
    let onSelectActivityType: (VenueActivityType) -> Void
    @State private var model: SessionBookModel
    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, activityType: VenueActivityType, onSelectActivityType: @escaping (VenueActivityType) -> Void) {
        self.onSelectActivityType = onSelectActivityType
        _model = State(initialValue: SessionBookModel(venueId: venueId, activityType: activityType))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.venue.data?.displayName ?? String(localized: "venue_book_title")))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let entry = model.entry.data { pickBar(entry) }
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
                } actions: {
                    Button("venue_book_back") { dismiss() }
                }
            } else {
                PulsoLoadErrorView(error) { model.refresh() }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sessions
                }
                .padding()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    VenueBookActivityTypeBar(activityTypes: model.activityTypes, selected: model.activityType, onSelect: onSelectActivityType)
                    if !model.dateKeys.isEmpty {
                        SpaceDateStrip(dateKeys: model.dateKeys, selected: model.dateKey) { model.selectDate($0) }
                    }
                }
                .padding(.vertical, PulsoSpace.s2)
                .background(palette.gray.step(2))
            }
        }
    }

    @ViewBuilder
    private var sessions: some View {
        if let entry = model.entry.data {
            if let rows = model.rows {
                if !model.isBookable {
                    Text((entry.venueStatus != .published ? "venue_book_unpublished" : "venue_book_entry_unpublished") as LocalizedStringKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("venue_session_title").font(.headline)
                if model.day.data?.bookable != true {
                    Text("venue_book_not_bookable").font(.subheadline).foregroundStyle(.secondary)
                } else if rows.isEmpty || rows.allSatisfy({ $0.row.slots.isEmpty }) {
                    Text("venue_session_none").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.row.id) { item in
                        SessionRowCard(
                            row: item.row,
                            option: item.option,
                            activityType: model.activityType,
                            timezone: entry.timezone,
                            bookable: model.isBookable,
                            picked: model.pick.flatMap { $0.optionId == item.row.optionId ? $0.startsAt : nil },
                            onPick: { model.select(optionId: item.row.optionId, startsAt: $0) }
                        )
                    }
                }
                Text(verbatim: localizedFormat("venue_session_rules", entry.bufferMinutes, entry.bookingWindowDays))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let error = model.day.error {
                PulsoLoadErrorView(error) { model.refresh() }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            }
        } else if let error = model.entry.error {
            PulsoLoadErrorView(error) { model.refresh() }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    /** 底部：选中的一场、人数（在主题 / 剧本的人数范围里）、价格，然后「去确认」。 */
    private func pickBar(_ entry: SessionEntryUi) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let option = model.pickedOption, let slot = model.pickedSlot {
                Text(verbatim: "\(option.name) · \(VenueTime.clock(slot.startsAt, timezone: entry.timezone))–\(VenueTime.clock(slot.endsAt, timezone: entry.timezone))")
                    .font(.subheadline.weight(.semibold))
                Stepper(value: Binding(get: { model.party }, set: { model.setPartySize($0) }), in: option.playersMin ... max(option.playersMin, option.playersMax)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(String(localized: "venue_session_party_size")) · \(model.party)").font(.subheadline)
                        Text(verbatim: option.extraPlayerAmount.map {
                            localizedFormat("venue_session_party_hint_extra", option.playersMin, option.playersMax, formatMoney($0, currency: entry.currency, locale: locale))
                        } ?? localizedFormat("venue_session_party_hint", option.playersMin, option.playersMax))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("venue_book_total").font(.subheadline.weight(.semibold))
                    Spacer()
                    PriceStack(listCents: model.pricing.totalListCents, payCents: model.pricing.totalPayCents, struck: model.pricing.struck, currency: entry.currency, emphasized: true)
                }
                if let level = model.bestMemberLevel, model.memberSaveCents > 0 {
                    MemberSaveHint(level: level, amount: formatMoney(Double(model.memberSaveCents) / 100, currency: entry.currency, locale: locale)) {
                        shell?.push(NearRoute.venue(venueId: model.venueId, sheet: .membership))
                    }
                }
            } else {
                Text("venue_session_empty").font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
                if let route = model.confirmRoute { shell?.push(route) }
            } label: {
                Text("venue_book_goto_confirm")
            }
            .buttonStyle(.pulso(fullWidth: true))
            .environment(\.pulsoControlSize, .comfortable)
            .disabled(!model.canGoToConfirm)
        }
        .padding(PulsoSpace.s4)
        .background(palette.accent.step(2).shadow(.drop(color: .black.opacity(0.08), radius: 4, y: -1)))
    }
}

/** 一个主题 / 剧本：名字、标签（难度或题材）、时长、人数，当天能开的时间。 */
private struct SessionRowCard: View {
    let row: SessionRowUi
    let option: SessionOptionUi?
    let activityType: VenueActivityType
    let timezone: String
    let bookable: Bool
    let picked: String?
    let onPick: (String) -> Void

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: row.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let tag {
                    VenueChip(text: tag, tone: RadixScale.blue.lightStep(9))
                }
            }
            HStack(spacing: 4) {
                VenueChip(text: localizedFormat("venue_session_minutes", row.durationMinutes), tone: RadixScale.slate.lightStep(9))
                if let option {
                    VenueChip(text: participantsLabel(minParticipants: option.playersMin, capacity: option.playersMax), tone: RadixScale.slate.lightStep(9))
                }
            }
            if !row.slots.contains(where: \.available) {
                Text("venue_session_full").font(.subheadline).foregroundStyle(.secondary)
            }
            PulsoFlowLayout(spacing: 8) {
                ForEach(row.slots, id: \.startsAt) { slot in
                    let isOn = picked == slot.startsAt
                    Button { onPick(slot.startsAt) } label: {
                        Text(verbatim: VenueTime.clock(slot.startsAt, timezone: timezone))
                            .font(.subheadline.monospacedDigit().weight(isOn ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .foregroundStyle(isOn ? palette.onAccent : palette.text)
                            .background(isOn ? palette.accent.step(9) : palette.accent.step(3), in: palette.chipShape)
                    }
                    .buttonStyle(.plain)
                    .disabled(!slot.available || !bookable)
                    .opacity(slot.available && bookable ? 1 : 0.4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: palette.cardShape)
    }

    /** 密室是难度，剧本杀是题材（没有题材时也用难度）。 */
    private var tag: String? {
        guard let option else { return nil }
        if activityType == .scriptMurder, let genre = option.subtitle, !genre.isEmpty { return genre }
        return String(localized: option.difficulty.labelResource)
    }
}
