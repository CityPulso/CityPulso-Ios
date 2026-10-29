import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动详情页（对应 Android `<Sport>Screen`，所有运动共用）：照片、标题、事实卡、我的报名、参与者、介绍、详情、装备、
 * 收费方式；底栏放价格和当前唯一可做的操作。报名 / 候补 / 退出等都在弹层里。
 * [openJoin]：从地图卡片点「报名」进来时，加载完且还能报名就直接打开报名弹层。
 */
struct EventDetailView: View {
    let openJoin: Bool

    @State private var model: EventDetailModel
    @State private var showEdit = false
    @State private var confirmEnd = false
    @State private var joinIntentHandled: Bool
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(sport: LoopSport, eventId: String, openJoin: Bool = false) {
        self.openJoin = openJoin
        _model = State(initialValue: EventDetailModel(sport: sport, eventId: eventId))
        _joinIntentHandled = State(initialValue: !openJoin)
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if model.event != nil {
                    EventDetailBottomBar(model: model, onEnd: { confirmEnd = true }, onOpenChecklist: { openChecklist() })
                }
            }
            .task { await model.observe() }
            .refreshable { model.refresh() }
            .onChange(of: model.rosterReady) { _, ready in
                guard ready, !joinIntentHandled else { return }
                joinIntentHandled = true
                if model.canJoinDirectly {
                    model.sheet = .join
                } else if model.canJoinWaitlist {
                    model.sheet = .waitlist
                }
            }
            .sheet(item: sheetBinding) { sheet in
                EventDetailSheetContent(sheet: sheet, model: model, onOpenProfile: { openProfile($0) })
                    .interactiveDismissDisabled(model.isActionInProgress)
            }
            .sheet(isPresented: paymentBinding) {
                if let session = model.paymentSession {
                    SeatPaymentSheet(session: session, pay: { try await model.pay($0) }, onPaid: { model.onPaid() }, onDismiss: { model.paymentSession = nil })
                }
            }
            .sheet(isPresented: $showEdit) {
                if let event = model.event {
                    EditBasicSheet(event: event) { title, venue, description, payee in
                        showEdit = false
                        Task { await model.patchBasic(title: title, venueName: venue, description: description, payeePaymentAccountId: payee) }
                    }
                }
            }
            .alert("event_detail_end_confirm_title", isPresented: $confirmEnd) {
                Button("event_detail_end_session", role: .destructive) { Task { await model.endEvent() } }
                Button("event_detail_dialog_cancel", role: .cancel) {}
            } message: {
                Text("event_detail_end_confirm_body")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let event = model.event {
            EventDetailBody(
                model: model,
                event: event,
                onOpenMap: openMap(event),
                onOpenHost: { openProfile(event.profileId) }
            )
        } else if let error = model.eventError {
            PulsoLoadErrorView(error) { model.refresh() }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let event = model.event {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.isHost, !event.isEnded {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(Text("event_detail_edit_basic"))
                }
                ShareLink(item: shareText(event)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("event_detail_share"))
            }
        }
    }

    /** 同一时间只开一个弹层；请求进行中不让关（Android `closeSheet`）。 */
    private var sheetBinding: Binding<EventSheet?> {
        Binding(get: { model.sheet }, set: { value in
            if value == nil { model.closeSheet() } else { model.sheet = value }
        })
    }

    private var paymentBinding: Binding<Bool> {
        Binding(get: { model.paymentSession != nil }, set: { if !$0 { model.paymentSession = nil } })
    }

    private func shareText(_ event: any SportFullEvent) -> String {
        localizedFormat(
            "event_detail_share_text",
            event.title.isEmpty ? String(localized: "explore_pin_untitled") : event.title,
            DateTimeFormatters.sessionDayClockRange(event.startsAt, event.endsAt, locale: locale),
            event.venueName ?? event.address ?? ""
        )
    }

    /** 有坐标就用系统地图打开（Android `geo:` intent）。 */
    private func openMap(_ event: any SportFullEvent) -> (() -> Void)? {
        guard let lat = event.locationLat, let lng = event.locationLng else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lng)"),
            URLQueryItem(name: "q", value: event.venueName ?? event.title),
        ]
        guard let url = components.url else { return nil }
        return { openURL(url) }
    }

    /** 社交主页在第 10 组移植。 */
    private func openProfile(_ profileId: String) {
        shell?.push(LoopRoute.comingSoon(title: "event_detail_participants_view_profile", systemImage: "person.crop.circle"))
    }

    /** 收款清单在本组稍后接上。 */
    private func openChecklist() {
        shell?.push(LoopRoute.comingSoon(title: "checklist_title", systemImage: "checklist"))
    }
}

/** 加到系统日历的预填内容（Android `addToCalendar`）。 */
func calendarDraft(_ event: any SportFullEvent) -> CalendarDraft? {
    CalendarDraft(
        title: event.title,
        startsAt: event.startsAt,
        endsAt: event.endsAt,
        location: event.venueName ?? event.address,
        notes: event.description
    )
}
