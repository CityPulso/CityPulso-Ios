import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 我的一条订场（Android `<Sport>CourtBookingScreen`，三种运动共用）：球馆头、状态横幅、取消、待付款时的付款面板、
 * 场地与价格、取消与退款（订场时的政策快照）、到场须知、我的信息、球馆联系方式、时间线。
 */
struct CourtBookingView: View {
    @State private var model: CourtBookingModel
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(sport: VenueSport, bookingId: String) {
        _model = State(initialValue: CourtBookingModel(sport: sport, bookingId: bookingId))
    }

    var body: some View {
        content
            .navigationTitle(Text(model.sport.loopSport.labelKey))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: Binding(get: { model.cancel != nil }, set: { if !$0 { model.cancel = nil } })) {
                if let booking = model.booking.data { cancelSheet(booking) }
            }
            .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        if let booking = model.booking.data {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                List {
                    header(booking)
                    Section { StatusBanner(booking: booking, paid: model.paid, now: context.date) }
                    if model.canCancel(now: context.date) {
                        Section {
                            Button("court_booking_cancel_button", role: .destructive) { model.openCancel() }
                        }
                    }
                    if model.needsPayment { paymentSection(booking) }
                    priceSection(booking)
                    Section {
                        CourtRefundPolicySummary(policy: booking.refundPolicy, tiers: booking.refundTiers, note: booking.refundPolicyNote)
                    } header: {
                        Text("court_booking_policy_title")
                    } footer: {
                        Text("court_booking_policy_snapshot")
                    }
                    if let instructions = booking.venueBookingInstructions, !instructions.trimmingCharacters(in: .whitespaces).isEmpty {
                        Section("court_booking_instructions") { Text(verbatim: instructions).font(.subheadline) }
                    }
                    if booking.contactName != nil || booking.contactPhone != nil || booking.note != nil {
                        Section("court_booking_your_details") {
                            ForEach([booking.contactName, booking.contactPhone, booking.note].compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) {
                                Text(verbatim: $0).font(.subheadline)
                            }
                        }
                    }
                    venueContactSection(booking)
                    timelineSection(booking)
                }
            }
            .refreshable { model.refresh() }
        } else if let error = model.booking.error {
            if error.kind == .notFound {
                ContentUnavailableView {
                    Label("court_booking_not_found", systemImage: "calendar.badge.exclamationmark")
                } actions: {
                    Button("court_booking_back") { shell?.push(LoopRoute.courtBookings) }
                }
            } else {
                PulsoLoadErrorView(error) { model.refresh() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ booking: MyCourtBookingUi) -> some View {
        Section {
            Button { shell?.push(LoopRoute.venue(venueId: booking.venueId)) } label: {
                HStack(spacing: 12) {
                    SportCover(url: model.imageURL(booking.venueCoverImageId), sport: booking.sport.loopSport, iconSize: 28)
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: booking.venueName).font(.headline).foregroundStyle(Color.primary)
                        Text(verbatim: VenueTime.range(booking.startsAt, booking.endsAt, timezone: booking.venueTimezone, locale: locale))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(booking.status.labelKey).font(.caption.weight(.semibold)).foregroundStyle(booking.status.tone)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func paymentSection(_ booking: MyCourtBookingUi) -> some View {
        Section("court_booking_pay_title") {
            if let session = model.payment?.data {
                HoldPaymentPanel(session: session, payee: booking.venueName, pay: { try await model.pay($0) }, onPaid: { model.onPaid() })
            } else if model.payment?.error != nil {
                Text("payments_hold_load_failed").font(.subheadline).foregroundStyle(.red)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    private func priceSection(_ booking: MyCourtBookingUi) -> some View {
        Section("court_booking_price_title") {
            ForEach(booking.priceBreakdown, id: \.self) { line in
                let court = booking.slots.first { $0.courtId == line.courtId }?.courtName ?? ""
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: court).font(.subheadline.weight(.medium))
                        Text(verbatim: "\(VenueTime.clock(line.startsAt, timezone: booking.venueTimezone))–\(VenueTime.clock(line.endsAt, timezone: booking.venueTimezone))" + (line.rateLabel.map { " · \($0)" } ?? ""))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: formatMoney(line.amount, currency: booking.currency, locale: locale)).font(.subheadline.monospacedDigit())
                }
            }
            HStack {
                Text("court_booking_total").font(.headline)
                Spacer()
                Text(verbatim: formatMoney(booking.totalAmount, currency: booking.currency, locale: locale)).font(.headline.monospacedDigit())
            }
            HStack(spacing: 6) {
                if let minutes = booking.bundleMinutes {
                    VenueChip(text: localizedFormat("venue_booking_bundle_used", formatBundleHours(minutes, locale: locale)), tone: RadixScale.blue.lightStep(9))
                }
                if booking.paidMarkedAt != nil {
                    VenueChip(text: String(localized: "court_booking_paid_at_venue"), tone: RadixScale.green.lightStep(9))
                }
                if booking.refundStatus == "succeeded", let refund = booking.refundAmount {
                    VenueChip(text: localizedFormat("court_booking_refunded", formatMoney(refund, currency: booking.currency, locale: locale)), tone: RadixScale.green.lightStep(9))
                }
            }
        }
    }

    @ViewBuilder
    private func venueContactSection(_ booking: MyCourtBookingUi) -> some View {
        Section("court_booking_venue_contact") {
            if !booking.venueAddress.isEmpty {
                Label { Text(verbatim: booking.venueAddress) } icon: { Image(systemName: "mappin.and.ellipse") }.font(.subheadline)
            }
            if let phone = booking.venuePhone, !phone.isEmpty, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                Button { openURL(url) } label: { Label { Text(verbatim: phone) } icon: { Image(systemName: "phone") } }
            }
        }
    }

    private func timelineSection(_ booking: MyCourtBookingUi) -> some View {
        let candidates: [(LocalizedStringKey, String?)] = [
            (LocalizedStringKey("court_booking_timeline_created"), booking.createdAt.isEmpty ? nil : booking.createdAt),
            (LocalizedStringKey("court_booking_timeline_confirmed"), booking.confirmedAt),
            (LocalizedStringKey("court_booking_timeline_paid_marked"), booking.paidMarkedAt),
            (LocalizedStringKey("court_booking_timeline_canceled"), booking.canceledAt),
            (LocalizedStringKey("court_booking_timeline_expired"), booking.expiredAt),
        ]
        let events: [(LocalizedStringKey, String)] = candidates.compactMap { label, at in at.map { (label, $0) } }
        return Section("court_booking_timeline_title") {
            ForEach(events.indices, id: \.self) { index in
                LabeledContent {
                    Text(verbatim: DateTimeFormatters.monthDayTime(events[index].1, locale: locale) ?? "").font(.caption.monospacedDigit())
                } label: {
                    Text(events[index].0).font(.subheadline)
                }
            }
        }
    }

    /** 取消：按付款方式说清退多少（或退回多少时长），可填原因。 */
    private func cancelSheet(_ booking: MyCourtBookingUi) -> some View {
        let dialog = model.cancel ?? CourtCancelDialogState()
        let preview = dialog.preview?.data
        let money = { (amount: Double) in formatMoney(amount, currency: booking.currency, locale: locale) }
        let outcome: String? = {
            if model.paidWithBundle {
                guard let preview else { return nil }
                let restore = preview.restoreMinutes ?? 0
                return restore > 0
                    ? localizedFormat("venue_booking_cancel_bundle_restore", formatBundleHours(restore, locale: locale), formatBundleHours(booking.bundleMinutes ?? 0, locale: locale))
                    : String(localized: "venue_booking_cancel_bundle_no_restore")
            }
            if !model.paidOnline {
                return String(localized: booking.status == .awaitingPayment ? "court_booking_cancel_not_charged" : "court_booking_cancel_pay_at_venue")
            }
            guard let preview else { return nil }
            return preview.refundAmount > 0
                ? localizedFormat("court_booking_cancel_refund", money(preview.refundAmount), money(preview.totalAmount))
                : String(localized: "court_booking_cancel_no_refund")
        }()
        return NavigationStack {
            Form {
                Section {
                    Text("court_booking_cancel_body").font(.subheadline)
                    if dialog.preview?.isLoading == true {
                        ProgressView()
                    } else if let outcome {
                        Text(verbatim: outcome).font(.subheadline.weight(.medium))
                    }
                    if model.paidOnline, let fee = preview?.providerFeeAmount, (preview?.refundAmount ?? 0) > 0 {
                        Text(verbatim: localizedFormat("court_booking_cancel_fee", money(fee))).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("court_booking_cancel_reason_placeholder", text: Binding(get: { model.cancel?.reason ?? "" }, set: { model.setCancelReason($0) }), axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                if let error = dialog.error {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("court_booking_cancel_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("court_booking_cancel_keep") { model.cancel = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        Task { await model.confirmCancel() }
                    } label: {
                        if dialog.submitting { ProgressView() } else { Text("court_booking_cancel_confirm") }
                    }
                    .disabled(dialog.submitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/** 订场状态横幅（Android `StatusBanner`）：每个状态一句话，待确认时显示保留倒计时和拨号。 */
private struct StatusBanner: View {
    let booking: MyCourtBookingUi
    let paid: Bool
    let now: Date

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        let money = { (amount: Double) in formatMoney(amount, currency: booking.currency, locale: locale) }
        switch booking.status {
        case .pending:
            let phone = booking.paymentMethod == .phone
            banner(RadixScale.amber.lightStep(9), phone ? "phone" : "hourglass") {
                Text(verbatim: phone ? localizedFormat("court_booking_banner_phone_pending", booking.venueName) : String(localized: "court_booking_banner_offline_pending"))
                if let expires = DateTimeFormatters.parseInstant(booking.expiresAt) {
                    let left = max(0, Int(expires.timeIntervalSince(now)))
                    Text(verbatim: "\(String(localized: "court_booking_banner_hold_left")) \(formatCountdown(left))").fontWeight(.semibold)
                }
                if phone, let venuePhone = booking.venuePhone, !venuePhone.isEmpty, let url = URL(string: "tel:\(venuePhone.filter { !$0.isWhitespace })") {
                    Button(localizedFormat("court_booking_banner_call", venuePhone)) { openURL(url) }
                        .buttonStyle(.bordered)
                }
            }
        case .awaitingApproval:
            banner(RadixScale.amber.lightStep(9), "hourglass") { Text("court_booking_banner_awaiting_approval") }
        case .awaitingPayment:
            banner(RadixScale.blue.lightStep(9), paid ? "hourglass" : "timer") {
                Text((paid ? "court_booking_banner_paid_confirming" : "court_booking_banner_awaiting_payment") as LocalizedStringKey)
            }
        case .confirmed:
            banner(RadixScale.green.lightStep(9), "checkmark.circle") {
                switch booking.paymentMethod {
                case .platform: Text("court_booking_banner_confirmed_paid")
                case .bundle: Text(verbatim: localizedFormat("venue_booking_banner_confirmed_bundle", formatBundleHours(booking.bundleMinutes ?? 0, locale: locale)))
                case .phone, .offline: Text("court_booking_banner_confirmed_pay_at_venue")
                }
            }
        case .canceled:
            banner(RadixScale.slate.lightStep(9), "xmark.circle") {
                switch booking.canceledBy {
                case .booker: Text("court_booking_banner_canceled_by_booker")
                case .venue: Text("court_booking_banner_canceled_by_venue")
                case .system, .none: Text("court_booking_banner_canceled_by_system")
                }
                if let refund = booking.refundAmount, let status = booking.refundStatus {
                    switch status {
                    case "pending": Text(verbatim: localizedFormat("court_booking_banner_refund_pending", money(refund)))
                    case "succeeded": Text(verbatim: localizedFormat("court_booking_banner_refund_succeeded", money(refund)))
                    default: Text(verbatim: localizedFormat("court_booking_banner_refund_failed", money(refund)))
                    }
                }
            }
        case .expired:
            banner(RadixScale.slate.lightStep(9), "clock") { Text("court_booking_banner_expired") }
        }
    }

    private func banner(_ tone: Color, _ systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tone)
            VStack(alignment: .leading, spacing: 6) { content() }
                .font(.subheadline)
        }
        .listRowBackground(tone.opacity(0.1))
    }
}

/** 小色块标签（Android `VenueChip`）。 */
struct VenueChip: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tone.opacity(0.14), in: .capsule)
    }
}
