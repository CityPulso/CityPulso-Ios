import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 教练面板（Android `CoachPanelScreen`）：课次、合作球馆、授课报酬、教练资料四个标签。 */
struct CoachPanelView: View {
    @State private var model = CoachPanelModel()
    @State private var confirm: PulsoHoldConfirm?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            PulsoUnderlineTabRow(CoachPanelTab.allCases, selection: $model.tab) { Text($0.labelKey) }
            list
        }
        .navigationTitle("coach_panel_title")
        .task { await model.observe() }
        .pulsoHoldConfirm($confirm)
        .sheet(item: $model.draft) { _ in CoachCreateSessionSheet(model: model) }
    }

    private var list: some View {
        List {
            switch model.tab {
            case .sessions: sessionsTab
            case .venues: venuesTab
            case .compensation: compensationTab
            case .profile:
                if model.profileLoaded {
                    CoachProfileForm(model: model)
                    if let profile = model.profile { servicesSection(sports: profile.sports) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
        }
        .refreshable { await model.refresh() }
    }

    /* ------------------------------ 课次 ------------------------------ */

    @ViewBuilder
    private var sessionsTab: some View {
        Section {
            Button { model.openDraft() } label: { Text("coach_panel_create").frame(maxWidth: .infinity) }
                .buttonStyle(.pulso())
                .disabled(model.partnerVenues.isEmpty)
                .listRowBackground(Color.clear)
        } footer: {
            if model.partnerVenues.isEmpty { Text("coach_panel_need_partner") }
        }
        Section {
            paged(model.sessions, emptyTitle: "coach_panel_sessions_empty", emptyBody: "coach_panel_sessions_empty_body") { session in
                sessionCard(session)
            }
        }
    }

    private func sessionCard(_ session: CoachingSession) -> some View {
        let live = session.venueState != .canceled && session.venueState != .completed
        let canRequest = session.venueState == .draft || session.venueState == .rejected
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: DateTimeFormatters.monthDayTime(session.startsAt, locale: locale) ?? "").font(.headline)
            Text(verbatim: [
                String(localized: session.venueState.labelResource), session.venueName, session.courtName, session.serviceTitle,
                formatMoney(session.priceAmount, currency: session.currency, locale: locale),
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let fee = session.bookingTotalAmount {
                Text(verbatim: localizedFormat("coach_panel_court_fee", formatMoney(fee, currency: session.currency, locale: locale))).font(.caption)
            }
            if session.venueState == .rejected, let reason = session.bookingCancelReason {
                Text(verbatim: reason).font(.caption).foregroundStyle(.red)
            }
            ForEach(session.participants ?? [], id: \.id) { participant in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: [
                        model.participantName(participant.profileId),
                        String(localized: participant.status.labelResource),
                        String(localized: participant.paymentStatus.labelResource),
                    ].joined(separator: " · "))
                        .font(.caption)
                    if live, participant.status == .accepted, participant.paymentStatus == .unpaid {
                        PulsoFlowLayout(spacing: 6) {
                            ForEach(CoachPanelModel.collectMethods, id: \.self) { method in
                                Button(method.collectLabelKey) { Task { await model.markPaid(session.id, profileId: participant.profileId, method: method) } }
                                    .buttonStyle(.pulso(.soft))
                            }
                            Button("coach_panel_waive") { Task { await model.markPaid(session.id, profileId: participant.profileId, method: nil) } }
                                .buttonStyle(.pulso(.soft))
                                .tint(.secondary)
                        }
                        .controlSize(.small)
                    }
                }
            }
            if live {
                PulsoFlowLayout(spacing: 6) {
                    if canRequest {
                        ForEach(CoachPanelModel.courtMethods, id: \.self) { method in
                            Button(localizedFormat("coach_panel_request_court", String(localized: method.courtLabelResource))) {
                                Task { await model.requestCourt(session.id, method: method) }
                            }
                            .buttonStyle(.pulso(.soft))
                        }
                    }
                    if session.venueState == .confirmed {
                        Button("coach_panel_complete") { Task { await model.completeSession(session.id) } }.buttonStyle(.pulso(.soft))
                    }
                    Button("coach_panel_cancel_session") {
                        confirm = PulsoHoldConfirm(
                            title: String(localized: "coach_panel_cancel_session_title"),
                            message: String(localized: "coach_panel_cancel_session_body"),
                            label: String(localized: "coach_panel_cancel_session")
                        ) { Task { await model.cancelSession(session.id) } }
                    }
                    .buttonStyle(.pulso(.soft))
                    .tint(.secondary)
                }
                .controlSize(.small)
                .disabled(model.busy)
            }
        }
        .padding(.vertical, 4)
    }

    /* ------------------------------ 球馆 ------------------------------ */

    @ViewBuilder
    private var venuesTab: some View {
        Section {
            paged(model.venues, emptyTitle: "coach_panel_venues_empty", emptyBody: nil, emptyAction: {
                Button("coach_panel_explore") { shell?.open(.explore) }.buttonStyle(.pulso())
            }) { link in
                venueRow(link)
            }
        } header: {
            Text("coach_panel_venues_hint").textCase(nil)
        }
    }

    private func venueRow(_ link: VenueCoach) -> some View {
        let active = link.status == .active
        return VStack(alignment: .leading, spacing: 6) {
            Button { shell?.push(LoopRoute.venue(venueId: link.venueId, sheet: nil)) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: link.venueName).font(.headline)
                    Text(verbatim: [String(localized: link.status.labelResource), link.certified ? String(localized: "coach_panel_certified") : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            HStack {
                if link.status == .pending, link.initiatedBy == .venue {
                    Button("coach_panel_accept") { Task { await model.answer(link.id, accept: true) } }.buttonStyle(.pulso())
                    Button("coach_panel_decline") { Task { await model.answer(link.id, accept: false) } }.buttonStyle(.pulso(.soft, tone: .gray))
                }
                if active || (link.status == .pending && link.initiatedBy == .coach) {
                    Button((active ? "coach_panel_leave" : "coach_panel_withdraw") as LocalizedStringKey) {
                        confirm = PulsoHoldConfirm(
                            title: String(localized: (active ? "coach_panel_leave_title" : "coach_panel_withdraw_title") as String.LocalizationValue),
                            message: localizedFormat(active ? "coach_panel_leave_body" : "coach_panel_withdraw_body", link.venueName),
                            label: String(localized: (active ? "coach_panel_leave" : "coach_panel_withdraw") as String.LocalizationValue)
                        ) { Task { await model.leave(link.id) } }
                    }
                    .buttonStyle(.pulso(.soft))
                    .tint(.secondary)
                }
            }
            .controlSize(.small)
            .disabled(model.busy)
        }
    }

    /* ------------------------------ 报酬 ------------------------------ */

    @ViewBuilder
    private var compensationTab: some View {
        Section("coach_panel_teaching") {
            let sessions = model.teaching.data ?? []
            if sessions.isEmpty, !model.teaching.isLoading {
                Text("coach_panel_no_teaching").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(sessions, id: \.id) { session in
                Text(verbatim: [
                    DateTimeFormatters.monthDayTime(session.startsAt, locale: locale) ?? "",
                    session.courseTitle,
                    (session.courts ?? []).map(\.courtName).joined(separator: ", "),
                ].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
            }
        }
        Section {
            PulsoHighlightTabRow(
                CoachCompensationStatus.allCases,
                selection: Binding(get: { model.compensationStatus }, set: { status in Task { await model.selectCompensationStatus(status) } })
            ) { Text($0.labelKey) }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            let items = model.compensations.data ?? []
            if items.isEmpty, !model.compensations.isLoading {
                ContentUnavailableView {
                    Text("coach_panel_compensation_empty")
                } description: {
                    Text("coach_panel_compensation_empty_body")
                }
            }
            ForEach(items, id: \.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.courseTitle).lineLimit(1)
                        Text(verbatim: [DateTimeFormatters.monthDayTime(item.startsAt, locale: locale), item.compensationNote].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: formatMoney(item.compensationAmount, currency: item.currency, locale: locale)).font(.subheadline.bold())
                        Text(item.compensationStatus.labelKey).font(.caption2)
                            .foregroundStyle(item.compensationStatus == .settled ? Color.accentColor : .orange)
                    }
                }
            }
        } footer: {
            Text("coach_panel_compensation_hint")
        }
    }

    /* ------------------------------ 服务 ------------------------------ */

    @ViewBuilder
    private func servicesSection(sports: [VenueSport]) -> some View {
        Section("coach_panel_services") {
            ForEach(model.services.filter { $0.status == .active }, id: \.id) { service in
                CoachServiceRow(model: model, service: service, sports: sports) {
                    confirm = PulsoHoldConfirm(
                        title: String(localized: "coach_panel_archive_title"),
                        message: String(localized: "coach_panel_archive_body"),
                        label: String(localized: "coach_panel_archive")
                    ) { Task { await model.archiveService(service.id) } }
                }
            }
        }
        Section {
            CoachServiceForm(model: model, existing: nil, sports: sports, onDone: {})
        }
    }

    /* ------------------------------ 公用 ------------------------------ */

    @ViewBuilder
    private func paged<Item: Identifiable & Sendable, Row: View, Action: View>(
        _ list: PagedList<Item, Int>, emptyTitle: LocalizedStringKey, emptyBody: LocalizedStringKey?,
        @ViewBuilder emptyAction: () -> Action = { EmptyView() }, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            ContentUnavailableView {
                Text(emptyTitle)
            } description: {
                if let emptyBody { Text(emptyBody) }
            } actions: {
                emptyAction()
            }
        } else {
            ForEach(list.items) { item in
                row(item).onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }
}

/** 教练资料表单：教的运动、简介、年限、收款方式、是否公开（Android `ProfileForm`）。 */
private struct CoachProfileForm: View {
    let model: CoachPanelModel
    @State private var headline = ""
    @State private var bio = ""
    @State private var years = ""
    @State private var cash = true
    @State private var etransfer = true
    @State private var wechat = false
    @State private var listed = true
    @State private var sports: Set<VenueSport> = [.badminton]
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        Section {
            ForEach(VenueSport.allCases, id: \.self) { sport in
                Toggle(sport.loopSport.labelKey, isOn: Binding(get: { sports.contains(sport) }, set: { on in if on { sports.insert(sport) } else { sports.remove(sport) } }))
            }
        } header: {
            Text("coach_panel_profile_title")
        } footer: {
            Text("coach_panel_sports")
        }
        Section {
            TextField("coach_panel_headline", text: $headline)
            TextField("coach_panel_bio", text: $bio, axis: .vertical).lineLimit(2 ... 6)
            TextField("coach_panel_years", text: Binding(get: { years }, set: { years = $0.filter(\.isNumber) })).keyboardType(.numberPad)
        }
        Section {
            Toggle("coach_panel_collect_cash", isOn: $cash)
            Toggle("coach_panel_collect_etransfer", isOn: $etransfer)
            Toggle("coach_panel_collect_wechat", isOn: $wechat)
            Button("coach_panel_payment_accounts") { shell?.push(LoopRoute.paymentAccounts) }
        } footer: {
            Text("coach_panel_platform_hint")
        }
        Section {
            Toggle("coach_panel_listed", isOn: $listed)
            Button {
                let profile = model.profile
                Task {
                    await model.saveProfile(SaveCoachProfileRequest(
                        headline: headline.trimmingCharacters(in: .whitespaces).isEmpty ? nil : headline.trimmingCharacters(in: .whitespaces),
                        bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bio.trimmingCharacters(in: .whitespacesAndNewlines),
                        sports: VenueSport.allCases.filter(sports.contains),
                        yearsExperience: Int(years),
                        certifications: profile?.certifications,
                        currency: profile?.currency ?? "CAD",
                        acceptsPlatform: profile?.acceptsPlatform ?? false,
                        acceptsCash: cash,
                        acceptsEtransfer: etransfer,
                        acceptsWechat: wechat,
                        payeeAccountId: profile?.payeePaymentAccountId,
                        listed: listed
                    ))
                }
            } label: {
                Text("coach_panel_save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pulso())
            .disabled(sports.isEmpty || model.busy)
            .listRowBackground(Color.clear)
        }
        .task(id: model.profile?.coachProfileId) { load() }
    }

    private func load() {
        let profile = model.profile
        headline = profile?.headline ?? ""
        bio = profile?.bio ?? ""
        years = profile?.yearsExperience.map(String.init) ?? ""
        cash = profile?.acceptsCash ?? true
        etransfer = profile?.acceptsEtransfer ?? true
        wechat = profile?.acceptsWechat ?? false
        listed = profile?.isListed ?? true
        sports = Set(profile?.sports ?? [.badminton])
    }
}

/** 一项服务：标题、运动 · 形式 · 时薪；编辑或归档（归档要按住确认）。 */
private struct CoachServiceRow: View {
    let model: CoachPanelModel
    let service: CoachingService
    let sports: [VenueSport]
    let onArchive: () -> Void
    @State private var editing = false
    @Environment(\.locale) private var locale

    var body: some View {
        if editing {
            CoachServiceForm(model: model, existing: service, sports: sports) { editing = false }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: service.title)
                    Text(verbatim: [
                        String(localized: service.sport.loopSport.labelResource),
                        String(localized: service.format.labelResource),
                        formatMoney(service.hourlyPriceAmount, currency: service.currency, locale: locale),
                    ].joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("coach_panel_edit") { editing = true }.buttonStyle(.pulso(.soft))
                Button("coach_panel_archive", action: onArchive).buttonStyle(.pulso(.soft, tone: .gray))
            }
            .controlSize(.small)
        }
    }
}

/** [existing] 为空是「添加服务」，否则编辑这项服务（整体替换）；[sports] 是教练教的运动。 */
private struct CoachServiceForm: View {
    let model: CoachPanelModel
    let existing: CoachingService?
    let sports: [VenueSport]
    let onDone: () -> Void
    @State private var sport: VenueSport?
    @State private var title = ""
    @State private var price = ""
    @State private var format = CoachingServiceFormat.oneOnOne

    private var options: [VenueSport] { sports.isEmpty ? VenueSport.allCases : sports }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((existing == nil ? "coach_panel_add_service" : "coach_panel_edit_service") as LocalizedStringKey).font(.subheadline.weight(.semibold))
            Picker("coach_panel_sports", selection: Binding(get: { sport ?? options[0] }, set: { sport = $0 })) {
                ForEach(options, id: \.self) { Text($0.loopSport.labelKey).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("coach_panel_service_title", text: $title)
            Picker("coach_panel_service", selection: $format) {
                ForEach(CoachingServiceFormat.allCases, id: \.self) { Text($0.labelKey).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("coach_panel_service_price", text: $price).keyboardType(.decimalPad)
            HStack {
                Button((existing == nil ? "coach_panel_add_service" : "coach_panel_save") as LocalizedStringKey) {
                    let picked = sport ?? options[0]
                    let name = title.trimmingCharacters(in: .whitespaces)
                    let hourly = Double(price) ?? 0
                    Task { await model.saveService(existing, sport: picked, title: name, format: format, hourlyPrice: hourly) }
                    if existing == nil {
                        title = ""
                        price = ""
                    }
                    onDone()
                }
                .buttonStyle(.pulso())
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                if existing != nil {
                    Button("coach_panel_cancel_edit", action: onDone).buttonStyle(.pulso(.soft, tone: .gray))
                }
            }
            .controlSize(.small)
        }
        .onAppear {
            sport = existing?.sport
            title = existing?.title ?? ""
            price = existing.map { String($0.hourlyPriceAmount) } ?? ""
            format = existing?.format ?? .oneOnOne
        }
    }
}

/** 新建私教课（单次或每周重复）；建好后列出每次课和场地申请的结果（Android `CreateSessionSheet`）。 */
private struct CoachCreateSessionSheet: View {
    @Bindable var model: CoachPanelModel
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                if let created = model.created {
                    Section {
                        ForEach(created.sessions, id: \.sessionId) { session in
                            let key: String.LocalizationValue = session.courtError != nil ? "coach_panel_created_taken" : session.bookingId != nil ? "coach_panel_created_requested" : "coach_panel_created_draft"
                            Text(verbatim: "\(DateTimeFormatters.monthDayTime(session.startsAt, locale: locale) ?? "") · \(String(localized: key))")
                                .foregroundStyle(session.courtError != nil ? .red : .primary)
                        }
                    }
                    Button("coach_panel_done") { model.closeDraft() }
                } else if model.draft != nil {
                    form
                }
            }
            .navigationTitle("coach_panel_create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.closeDraft() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var form: some View {
        Section("coach_panel_venue") {
            Picker("coach_panel_venue", selection: draft(\.venueId)) {
                ForEach(model.partnerVenues, id: \.venueId) { Text(verbatim: $0.venueName).tag(Optional($0.venueId)) }
            }
            let sports = (model.profile?.sports).flatMap { $0.isEmpty ? nil : $0 } ?? VenueSport.allCases
            Picker("coach_panel_sports", selection: Binding(get: { model.draft?.sport ?? .badminton }, set: { sport in
                model.draft?.sport = sport
                model.draft?.serviceId = model.services.first { $0.sport == sport }?.id
            })) {
                ForEach(sports, id: \.self) { Text($0.loopSport.labelKey).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        Section("coach_panel_court") {
            Picker("coach_panel_court", selection: draft(\.courtId)) {
                ForEach(model.courts, id: \.id) { Text(verbatim: $0.name).tag(Optional($0.id)) }
            }
        }
        let services = model.services.filter { $0.status == .active && $0.sport == model.draft?.sport }
        if !services.isEmpty {
            Section("coach_panel_service") {
                Picker("coach_panel_service", selection: draft(\.serviceId)) {
                    ForEach(services, id: \.id) { Text(verbatim: $0.title).tag(Optional($0.id)) }
                }
            }
        }
        Section {
            PulsoWheelDatePicker("coach_panel_starts_at", selection: Binding(get: { model.draft?.startsAt ?? .now }, set: { model.draft?.startsAt = $0 }), in: Date.now...)
            Stepper(value: Binding(get: { model.draft?.minutes ?? 60 }, set: { model.draft?.minutes = $0 }), in: 30 ... 480, step: 15) {
                LabeledContent("coach_panel_minutes") { Text(verbatim: "\(model.draft?.minutes ?? 60)") }
            }
            Stepper(value: Binding(get: { model.draft?.weeks ?? 1 }, set: { model.draft?.weeks = $0 }), in: 1 ... 26) {
                LabeledContent("coach_panel_weeks") { Text(verbatim: "\(model.draft?.weeks ?? 1)") }
            }
            TextField("coach_panel_price", text: Binding(get: { model.draft?.price ?? "" }, set: { model.draft?.price = $0 })).keyboardType(.decimalPad)
        }
        Section("coach_panel_participants") {
            if model.friends.isEmpty { Text("coach_panel_no_friends").font(.footnote) }
            ForEach(model.friends, id: \.friendProfileId) { friend in
                Toggle(isOn: Binding(
                    get: { model.draft?.participants.contains(friend.friendProfileId) ?? false },
                    set: { on in if on { model.draft?.participants.insert(friend.friendProfileId) } else { model.draft?.participants.remove(friend.friendProfileId) } }
                )) {
                    Text(verbatim: friend.profile.displayName ?? friend.friendProfileId)
                }
            }
        }
        Section {
            Toggle("coach_panel_request_now", isOn: Binding(get: { model.draft?.requestCourt ?? true }, set: { model.draft?.requestCourt = $0 }))
            if model.draft?.requestCourt == true {
                Picker("coach_panel_request_now", selection: Binding(get: { model.draft?.courtMethod ?? .platform }, set: { model.draft?.courtMethod = $0 })) {
                    ForEach(CoachPanelModel.courtMethods, id: \.self) { Text($0.courtLabelKey).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        if let error = model.draftError {
            Text(verbatim: error).font(.footnote).foregroundStyle(.red)
        }
        Section {
            Button { Task { await model.createSessions() } } label: {
                if model.busy { ProgressView().frame(maxWidth: .infinity) } else { Text("coach_panel_submit").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.pulso())
            .disabled(model.draft?.venueId == nil || model.draft?.courtId == nil || model.busy)
            .listRowBackground(Color.clear)
        }
    }

    private func draft<T>(_ path: WritableKeyPath<CoachSessionDraft, T?>) -> Binding<T?> {
        Binding(get: { model.draft?[keyPath: path] }, set: { model.draft?[keyPath: path] = $0 })
    }
}

extension CoachPanelTab {
    var labelKey: LocalizedStringKey {
        switch self {
        case .sessions: "coach_panel_tab_sessions"
        case .venues: "coach_panel_tab_venues"
        case .compensation: "coach_panel_tab_compensation"
        case .profile: "coach_panel_tab_profile"
        }
    }
}

extension CourtBookingPaymentMethod {
    var courtLabelKey: LocalizedStringKey {
        switch self {
        case .platform: "coach_panel_court_platform"
        case .offline: "coach_panel_court_offline"
        default: "coach_panel_court_phone"
        }
    }

    var courtLabelResource: String.LocalizationValue {
        switch self {
        case .platform: "coach_panel_court_platform"
        case .offline: "coach_panel_court_offline"
        default: "coach_panel_court_phone"
        }
    }
}

extension CoachingPaymentMethod {
    var collectLabelKey: LocalizedStringKey {
        switch self {
        case .etransfer: "coach_panel_collect_etransfer"
        case .wechat: "coach_panel_collect_wechat"
        default: "coach_panel_collect_cash"
        }
    }
}

extension VenueCoach: Identifiable {}
