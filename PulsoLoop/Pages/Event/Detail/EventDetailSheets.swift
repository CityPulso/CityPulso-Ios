import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

private let noteMaxLength = 200

/** 按 [EventSheet] 选弹层内容。 */
struct EventDetailSheetContent: View {
    let sheet: EventSheet
    let model: EventDetailModel
    let onOpenProfile: (String) -> Void

    var body: some View {
        switch sheet {
        case .join: JoinSheet(model: model, waitlist: false)
        case .waitlist: JoinSheet(model: model, waitlist: true)
        case .joinSuccess: JoinSuccessSheet(model: model, waitlisted: false)
        case .waitlistSuccess: JoinSuccessSheet(model: model, waitlisted: true)
        case .myRegistration: MyRegistrationSheet(model: model)
        case .exit: ExitSheet(model: model)
        case .participants: ParticipantsSheet(model: model, onOpenProfile: onOpenProfile)
        }
    }
}

/** 弹层统一外壳：可滚动、两侧留白（Android `<Sport>Sheet`）。 */
private struct SheetScaffold<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding()
                .padding(.top, 8)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct SheetHeading: View {
    let title: LocalizedStringKey
    var message: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            if let message { message.font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

/* ------------------------------ 报名 / 候补 ------------------------------ */

/** 报名付款信息（Android `JoinPayOptions`，对齐 WEB Registration modal）。 */
private struct JoinPayOptions {
    let priceLabel: String?
    let acceptsStripe: Bool
    let offersChoice: Bool
    let offlineLabel: String

    @MainActor
    init(model: EventDetailModel, locale: Locale) {
        let event = model.event
        priceLabel = event.flatMap { event in event.isFree ? nil : event.priceAmount.map { formatMoney($0, currency: event.currency, locale: locale) } }
        acceptsStripe = model.acceptsStripe
        offersChoice = model.offersPayChoice
        offlineLabel = model.offlineMethods.map(\.joinLabel).joined(separator: " · ")
    }

    func paysByCard(_ choice: RegistrationPayChoice) -> Bool {
        priceLabel != nil && acceptsStripe && (!offersChoice || choice == .card)
    }
}

/** 报名 / 候补弹层：谁来报名、给发起人的备注、（候补）最晚几小时前、怎么付、确认。 */
private struct JoinSheet: View {
    let model: EventDetailModel
    let waitlist: Bool

    @State private var note = ""
    @State private var hours = ""
    @State private var choice = RegistrationPayChoice.card
    @Environment(\.locale) private var locale

    var body: some View {
        let pay = JoinPayOptions(model: model, locale: locale)
        let loading = model.isActionInProgress
        SheetScaffold {
            if waitlist {
                SheetHeading(title: "event_detail_waitlist_dialog_title", message: Text("event_waitlist_body"))
            } else {
                SheetHeading(title: "event_detail_join_confirm_title", message: Text("event_detail_join_confirm_message"))
            }
            ViewerCard(model: model)
            if waitlist {
                VStack(alignment: .leading, spacing: 6) {
                    Text("event_detail_waitlist_hours_label").font(.subheadline.weight(.semibold))
                    TextField("event_waitlist_hours_placeholder", text: $hours)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: hours) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(3))
                            if digits != value { hours = digits }
                        }
                    Text("event_detail_waitlist_dialog_hint").font(.caption).foregroundStyle(.secondary)
                }
                .disabled(loading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("event_join_note_label").font(.subheadline.weight(.semibold))
                TextField("event_join_note_placeholder", text: $note, axis: .vertical)
                    .lineLimit(3 ... 5)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: note) { _, value in
                        if value.count > noteMaxLength { note = String(value.prefix(noteMaxLength)) }
                    }
                Text(verbatim: localizedFormat("event_join_note_count", note.count, noteMaxLength)).font(.caption).foregroundStyle(.secondary)
            }
            .disabled(loading)
            JoinPayChoice(pay: pay, queue: waitlist, choice: $choice)
            if let error = model.actionError {
                Text(verbatim: error).font(.footnote).foregroundStyle(.red)
            }
            Button {
                let trimmed = note.isEmpty ? nil : note
                Task {
                    await model.join(waitlistHoursBeforeStart: waitlist ? Int(hours) : nil, payChoice: choice, playerNote: trimmed)
                }
            } label: {
                Group {
                    if loading {
                        ProgressView()
                    } else if waitlist {
                        Text("event_detail_waitlist_confirm")
                    } else {
                        Text((pay.paysByCard(choice) ? "event_join_registration_confirm_pay" : "event_detail_join_confirm") as LocalizedStringKey)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pulso())
            .controlSize(.large)
            .disabled(loading)
        }
    }
}

/** 「个人信息」：占这个名额的当前身份。 */
private struct ViewerCard: View {
    let model: EventDetailModel

    var body: some View {
        let name = model.viewerDisplayName ?? String(localized: "explore_pin_untitled")
        VStack(alignment: .leading, spacing: 8) {
            Text("event_join_personal_info").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                PulsoAvatar(url: model.imageURL(model.viewerAvatarImageId), size: 40, fallbackText: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(.body.weight(.semibold)).lineLimit(1)
                    if let username = model.viewerUsername {
                        Text(verbatim: "@\(username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
        }
    }
}

/** 同时收刷卡和线下方式时让报名者选；只收刷卡时说明一句（Android `JoinPayChoice`）。 */
private struct JoinPayChoice: View {
    let pay: JoinPayOptions
    let queue: Bool
    @Binding var choice: RegistrationPayChoice

    var body: some View {
        if let price = pay.priceLabel {
            let cardBody: LocalizedStringKey = queue ? "event_join_registration_pay_card_queue_body" : "event_join_registration_pay_card_body"
            VStack(alignment: .leading, spacing: 8) {
                if pay.offersChoice {
                    Text(verbatim: localizedFormat("event_join_registration_pay_how", price)).font(.body.weight(.medium))
                    option(.card, systemImage: "creditcard", title: "event_join_registration_pay_card", body: Text(cardBody))
                    option(
                        .direct,
                        systemImage: "banknote",
                        title: "event_join_registration_pay_direct",
                        body: Text(verbatim: localizedFormat("event_join_registration_pay_direct_body", pay.offlineLabel))
                    )
                } else if pay.acceptsStripe {
                    Text(cardBody).font(.footnote).foregroundStyle(.secondary)
                }
                if pay.paysByCard(choice) {
                    Callout(tint: .blue, systemImage: "info.circle") { Text("event_join_registration_no_platform_fee") }
                }
            }
        }
    }

    private func option(_ value: RegistrationPayChoice, systemImage: String, title: LocalizedStringKey, body: Text) -> some View {
        let selected = choice == value
        return Button { choice = value } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: systemImage).font(.body.weight(.semibold))
                    body.font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : Color(.separator)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/* ------------------------------ 成功 / 我的报名 ------------------------------ */

/** 报名成功 / 已加入候补：大图标、活动事实和小贴士；按钮关闭或加到日历。 */
private struct JoinSuccessSheet: View {
    let model: EventDetailModel
    let waitlisted: Bool

    @State private var calendar: CalendarDraft?

    var body: some View {
        if let event = model.event {
            SheetScaffold {
                VStack(spacing: 12) {
                    HeroMark(systemImage: waitlisted ? "hourglass" : "checkmark", tint: waitlisted ? .orange : .green)
                    Text((waitlisted ? "event_waitlist_success_title" : "event_join_success_title") as LocalizedStringKey).font(.title2.bold())
                    Group {
                        if waitlisted {
                            Text("event_waitlist_success_body")
                        } else {
                            Text(verbatim: localizedFormat("event_join_success_body", event.title.isEmpty ? String(localized: "explore_pin_untitled") : event.title))
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                Button { model.closeSheet() } label: { Text("event_join_success_view_event").frame(maxWidth: .infinity) }
                    .buttonStyle(.pulso())
                    .controlSize(.large)
                Button { calendar = calendarDraft(event) } label: { Text("event_join_success_add_calendar").frame(maxWidth: .infinity) }
                    .buttonStyle(.pulso(.soft))
                    .controlSize(.large)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("event_detail_details_title").font(.subheadline.weight(.semibold))
                    EventFactLines(event: event)
                    FactLine(systemImage: "person", text: model.hostDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "event_detail_host_organizer"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("event_join_success_tips_title").font(.subheadline.weight(.semibold))
                    TipLine("event_join_success_tip_arrive")
                    TipLine("event_join_success_tip_gear")
                    TipLine("event_join_success_tip_cancel")
                }
            }
            .calendarEditor($calendar)
        }
    }
}

/** 我的报名：封面和状态、活动事实、付款状态、报名信息，以及加日历 / 取消。 */
private struct MyRegistrationSheet: View {
    let model: EventDetailModel

    @State private var calendar: CalendarDraft?
    @Environment(\.locale) private var locale

    var body: some View {
        if let event = model.event, let registration = model.myRegistration {
            SheetScaffold {
                SheetHeading(title: "event_my_registration_title")
                HStack(spacing: 12) {
                    SportCover(url: model.imageURLs.first, sport: event.sport, iconSize: 28)
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        EventTitle(title: event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        HStack(spacing: 8) {
                            EventTag(Text(registration.status.labelKey), accent: true, image: Image(systemName: "checkmark.circle"))
                            if !model.offlineMethods.isEmpty, !registration.usesPlatformPayment, !event.isFree {
                                EventTag(Text("event_detail_section_payment"))
                            }
                        }
                    }
                }
                EventFactLines(event: event)
                if registration.hasPaymentState {
                    MyRegistrationPaymentCard(model: model, registration: registration, currency: event.currency)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("event_my_registration_info").font(.subheadline.weight(.semibold))
                    InfoRow(label: "event_my_registration_people", value: Text(verbatim: localizedFormat("event_my_registration_people_value", 1)))
                    InfoRow(label: "event_my_registration_time", value: Text(verbatim: DateTimeFormatters.monthDayTime(registration.createdAt, locale: locale) ?? "—"))
                    InfoRow(label: "event_my_registration_amount", value: amount(event))
                    if !event.isFree {
                        InfoRow(
                            label: "event_my_registration_method",
                            value: Text((registration.usesPlatformPayment ? "event_join_registration_payment_methods_stripe" : "event_join_registration_pay_direct") as LocalizedStringKey)
                        )
                        InfoRow(label: "event_my_registration_status", value: Text(feeStatus(registration)), emphasis: true)
                    }
                    if let note = registration.playerNote, !note.isEmpty {
                        InfoRow(label: "event_join_note_label", value: Text(verbatim: note))
                    }
                }
                HStack(spacing: 8) {
                    Button { calendar = calendarDraft(event) } label: {
                        Label("event_join_success_add_calendar", systemImage: "calendar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pulso(.soft))
                    if model.isHost {
                        HostCannotExitButton()
                    } else if model.canExit {
                        Button { model.sheet = .exit } label: { Text("event_detail_cancel_registration").frame(maxWidth: .infinity) }
                            .buttonStyle(.pulso(.soft))
                            .tint(.secondary)
                    }
                }
            }
            .calendarEditor($calendar)
        }
    }

    private func amount(_ event: any SportFullEvent) -> Text {
        if event.isFree { return Text("shell_calendar_badge_free") }
        return Text(verbatim: event.priceAmount.map { formatMoney($0, currency: event.currency, locale: locale) } ?? "—")
    }

    private func feeStatus(_ registration: any SportRegistration) -> LocalizedStringKey {
        if registration.refund == .pending { return "event_my_registration_status_refunding" }
        if registration.refund == .succeeded { return "event_my_registration_status_refunded" }
        if registration.paidAt != nil { return "event_my_registration_status_paid" }
        if registration.status == .awaitingPayment || registration.usesPlatformPayment { return "event_my_registration_status_unpaid" }
        return "event_my_registration_status_offline"
    }
}

/* ------------------------------ 退出 ------------------------------ */

/** 取消报名 / 退出候补：说清刷卡的钱会怎样，再按住确认。请求进行中不能关。 */
private struct ExitSheet: View {
    let model: EventDetailModel

    @Environment(\.locale) private var locale

    private var waitlisted: Bool { model.myRegistration?.status == .waitlisted }

    var body: some View {
        if let event = model.event {
            SheetScaffold {
                VStack(spacing: 12) {
                    HeroMark(systemImage: "exclamationmark.triangle", tint: .orange)
                    Text((waitlisted ? "event_detail_leave_queue_confirm_title" : "event_detail_exit_confirm_title") as LocalizedStringKey).font(.title2.bold())
                    Text((waitlisted ? "event_detail_leave_queue_confirm_message" : "event_detail_exit_confirm_message") as LocalizedStringKey)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if let note = refundNote(event) {
                        Text(verbatim: note).font(.body)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                if let error = model.actionError {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.red)
                }
                HStack(spacing: 8) {
                    Button { model.closeSheet() } label: { Text("event_exit_keep").frame(maxWidth: .infinity, minHeight: 36) }
                        .buttonStyle(.pulso(.soft))
                        .tint(.secondary)
                        .disabled(model.isActionInProgress)
                    PulsoHoldButton(waitlisted ? "event_exit_confirm_waitlist" : "event_exit_confirm", loading: model.isActionInProgress) {
                        Task { await model.exit() }
                    }
                }
                Text("pulso_ui_hold_to_confirm", bundle: .pulsoLinkUI)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /** 刷卡付过的：免费退出期内原路退回，过了就不退。 */
    private func refundNote(_ event: any SportFullEvent) -> String? {
        guard let registration = model.myRegistration, registration.usesPlatformPayment, registration.paidAt != nil,
              let price = event.priceAmount, let start = DateTimeFormatters.parseInstant(event.startsAt)
        else { return nil }
        let amount = formatMoney(price, currency: event.currency, locale: locale)
        let freeUntil = event.freeExitHoursBeforeStart.map { start.addingTimeInterval(-Double($0) * 3600) }
        let stillFree = event.allowsFreeExit && (freeUntil.map { Date.now < $0 } ?? true)
        return localizedFormat(stillFree ? "event_exit_refund_note" : "event_exit_no_refund_note", amount)
    }
}

/* ------------------------------ 参与者 ------------------------------ */

/** 参与者：全部 / 已报名 / 候补三个分段，每人一行带「查看主页」，滚到底加载更多。 */
private struct ParticipantsSheet: View {
    let model: EventDetailModel
    let onOpenProfile: (String) -> Void

    @State private var tab = ParticipantsTab.all

    private var rows: [any SportRegistration] {
        switch tab {
        case .all: model.seatedRegistrations + model.waitlistedRegistrations
        case .joined: model.seatedRegistrations
        case .waitlist: model.waitlistedRegistrations
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $tab) {
                        Text(verbatim: localizedFormat("event_detail_participants_all", model.seatedRegistrations.count + model.waitlistedRegistrations.count)).tag(ParticipantsTab.all)
                        Text(verbatim: localizedFormat("event_detail_participants_joined", model.seatedRegistrations.count)).tag(ParticipantsTab.joined)
                        Text(verbatim: localizedFormat("event_detail_participants_waitlist", model.waitlistedRegistrations.count)).tag(ParticipantsTab.waitlist)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if model.isRosterLoading, !model.rosterReady {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if model.rosterError != nil, !model.rosterReady {
                    VStack(spacing: 8) {
                        Text("event_detail_roster_load_failed").foregroundStyle(.secondary)
                        Button("shell_home_retry") { model.refresh() }.buttonStyle(.pulso(.soft))
                    }
                    .frame(maxWidth: .infinity)
                } else if rows.isEmpty {
                    ContentUnavailableView {
                        Text((tab == .waitlist ? "event_detail_roster_empty_waitlist" : "event_detail_roster_empty_participating") as LocalizedStringKey)
                    }
                } else {
                    Section {
                        ForEach(rows, id: \.id) { registration in
                            ParticipantRow(model: model, registration: registration) { onOpenProfile(registration.profileId) }
                                .onAppear {
                                    if registration.id == rows.last?.id { Task { await model.loadMoreRoster() } }
                                }
                        }
                        if model.isRosterLoadingMore {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } footer: {
                        Label("event_detail_participants_privacy", systemImage: "lock").font(.caption)
                    }
                }
            }
            .navigationTitle(Text(verbatim: localizedFormat("event_detail_participants_title", model.activeSeats, model.event?.capacity ?? 0)))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if model.event?.isEnded != true {
                    Text(verbatim: seatsLeftLabel(model)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ParticipantRow: View {
    let model: EventDetailModel
    let registration: any SportRegistration
    let onOpenProfile: () -> Void

    @State private var showPendingExitHelp = false

    var body: some View {
        HStack(spacing: 12) {
            PulsoAvatar(url: model.imageURL(registration.avatarImageId), size: 40, systemImage: "person", fallbackText: registration.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: registration.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "explore_pin_untitled"))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(registration.status.labelKey).font(.caption).foregroundStyle(.secondary)
                    if registration.status == .pendingExit {
                        Button { showPendingExitHelp = true } label: { Image(systemName: "questionmark.circle").font(.caption) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .popover(isPresented: $showPendingExitHelp) {
                                Text("event_detail_participants_pending_exit_help").padding().presentationCompactAdaptation(.popover)
                            }
                    }
                }
            }
            Spacer(minLength: 0)
            Button("event_detail_participants_view_profile", action: onOpenProfile)
                .buttonStyle(.pulso(.soft))
                .controlSize(.small)
        }
    }
}

/* ------------------------------ 付款 / 编辑 ------------------------------ */

/** 占座付款（报名后或「立即付款」）：Stripe 付款面板，或稍后再付。 */
struct SeatPaymentSheet: View {
    let session: PaymentHoldSession
    let pay: (String) async throws -> PaymentAttempt
    let onPaid: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SheetScaffold {
            SheetHeading(title: "event_join_registration_pay_title", message: Text("event_join_registration_pay_body"))
            HoldPaymentPanel(session: session, payee: String(localized: "event_join_registration_host_payee"), pay: pay, onPaid: onPaid)
            Button(action: onDismiss) { Text("event_join_registration_pay_later").frame(maxWidth: .infinity) }
                .buttonStyle(.pulso(.soft))
                .tint(.secondary)
                .controlSize(.large)
        }
    }
}

/** 发起人改标题、地点、介绍；收费活动还能开关刷卡并选收款账户（Android `<Sport>EditBasicDialog`）。 */
struct EditBasicSheet: View {
    let event: any SportFullEvent
    let onSave: (_ title: String, _ venue: String, _ description: String, _ payeePaymentAccountId: String?) -> Void

    @State private var title: String
    @State private var venue: String
    @State private var description: String
    @State private var acceptsCard: Bool
    @State private var payeeId: String?
    @State private var payeeMissing = false
    @Environment(\.dismiss) private var dismiss

    init(event: any SportFullEvent, onSave: @escaping (String, String, String, String?) -> Void) {
        self.event = event
        self.onSave = onSave
        _title = State(initialValue: event.title)
        _venue = State(initialValue: event.venueName ?? "")
        _description = State(initialValue: event.description ?? "")
        _acceptsCard = State(initialValue: event.payeePaymentAccountId != nil)
        _payeeId = State(initialValue: event.payeePaymentAccountId)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("event_detail_edit_title", text: $title)
                TextField("event_detail_edit_venue", text: $venue)
                TextField("event_detail_edit_description", text: $description, axis: .vertical).lineLimit(3 ... 8)
                if !event.isFree {
                    Section {
                        Toggle(isOn: $acceptsCard) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("event_detail_host_edit_accepts_card")
                                Text("event_detail_host_edit_accepts_card_hint").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: acceptsCard) { payeeMissing = false }
                        if acceptsCard {
                            PaymentAccountPicker(
                                selectedId: $payeeId,
                                errorText: payeeMissing ? "event_detail_host_edit_payment_account_required" : nil
                            )
                            .onChange(of: payeeId) { payeeMissing = false }
                        }
                    }
                }
            }
            .navigationTitle(Text("event_detail_edit_basic"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("event_detail_dialog_cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("event_detail_dialog_save") {
                        if acceptsCard, payeeId == nil {
                            payeeMissing = true
                        } else {
                            onSave(title, venue, description, acceptsCard ? payeeId : nil)
                        }
                    }
                }
            }
        }
    }
}

/* ------------------------------ 小零件 ------------------------------ */

/** 时间和地点两行（成功弹层、我的报名共用）。 */
private struct EventFactLines: View {
    let event: any SportFullEvent

    @Environment(\.locale) private var locale

    var body: some View {
        let time = DateTimeFormatters.sessionDayClockRange(event.startsAt, event.endsAt, locale: locale)
        let place = [event.venueName, event.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        FactLine(systemImage: "calendar", text: time.isEmpty ? event.startsAt : time)
        FactLine(systemImage: "mappin.and.ellipse", text: place.isEmpty ? String(localized: "event_detail_court_tbd") : place)
    }
}

private struct FactLine: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: systemImage).foregroundStyle(.secondary) }
            .font(.body)
    }
}

private struct TipLine: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Label { Text(key).foregroundStyle(.secondary) } icon: { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            .font(.body)
    }
}

private struct InfoRow: View {
    let label: LocalizedStringKey
    let value: Text
    var emphasis = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value
                .fontWeight(emphasis ? .semibold : .regular)
                .foregroundStyle(emphasis ? Color.accentColor : Color.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
    }
}

private struct HeroMark: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 72, height: 72)
            .background(tint.opacity(0.14), in: .circle)
    }
}

private extension View {
    /** 弹出系统「新建日程」（在弹层里也能叠在上面）。 */
    func calendarEditor(_ draft: Binding<CalendarDraft?>) -> some View {
        sheet(item: draft) { value in
            CalendarEventEditor(draft: value) { draft.wrappedValue = nil }.ignoresSafeArea()
        }
    }
}
