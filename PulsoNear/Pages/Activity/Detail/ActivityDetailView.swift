import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动详情页（对应 Android `<ActivityType>Screen`，所有活动类型共用）：照片、标题、事实卡、我的报名、参与者、介绍、详情、装备、
 * 收费方式；底栏放价格和当前唯一可做的操作。报名 / 候补 / 退出等都在弹层里。
 * [openJoin]：从地图卡片点「报名」进来时，加载完且还能报名就直接打开报名弹层。
 */
struct ActivityDetailView: View {
    let openJoin: Bool

    @State private var model: ActivityDetailModel
    @State private var showEdit = false
    @State private var confirmEnd = false
    @State private var joinIntentHandled: Bool
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(activityType: NearActivityKind, activityId: String, openJoin: Bool = false) {
        self.openJoin = openJoin
        _model = State(initialValue: ActivityDetailModel(activityType: activityType, activityId: activityId))
        _joinIntentHandled = State(initialValue: !openJoin)
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if model.activity != nil {
                    ActivityDetailBottomBar(model: model, onEnd: { confirmEnd = true }, onOpenChecklist: { openChecklist() })
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
                ActivityDetailSheetContent(sheet: sheet, model: model, onOpenProfile: { openProfile($0) })
                    .interactiveDismissDisabled(model.isActionInProgress)
            }
            .sheet(isPresented: paymentBinding) {
                if let session = model.paymentSession {
                    SeatPaymentSheet(session: session, pay: { try await model.pay($0) }, onPaid: { model.onPaid() }, onDismiss: { model.paymentSession = nil })
                }
            }
            .sheet(isPresented: $showEdit) {
                if let activity = model.activity {
                    EditBasicSheet(activity: activity) { title, variant, venue, description, payee in
                        showEdit = false
                        Task { await model.patchBasic(title: title, mahjongVariant: variant, venueName: venue, description: description, payeePaymentAccountId: payee) }
                    }
                }
            }
            .alert("activity_detail_end_confirm_title", isPresented: $confirmEnd) {
                Button("activity_detail_end_activity", role: .destructive) { Task { await model.endActivity() } }
                Button("activity_detail_dialog_cancel", role: .cancel) {}
            } message: {
                Text("activity_detail_end_confirm_body")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let activity = model.activity {
            ActivityDetailBody(
                model: model,
                activity: activity,
                onOpenMap: openMap(activity),
                onOpenHost: { openProfile(activity.profileId) }
            )
        } else if let error = model.activityError {
            PulsoLoadErrorView(error) { model.refresh() }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let activity = model.activity {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.isHost, !activity.isEnded {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(Text("activity_detail_edit_basic"))
                }
                ShareLink(item: shareText(activity)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("activity_detail_share"))
            }
        }
    }

    /** 同一时间只开一个弹层；请求进行中不让关（Android `closeSheet`）。 */
    private var sheetBinding: Binding<ActivitySheet?> {
        Binding(get: { model.sheet }, set: { value in
            if value == nil { model.closeSheet() } else { model.sheet = value }
        })
    }

    private var paymentBinding: Binding<Bool> {
        Binding(get: { model.paymentSession != nil }, set: { if !$0 { model.paymentSession = nil } })
    }

    private func shareText(_ activity: any ActivityTypeFullActivity) -> String {
        localizedFormat(
            "activity_detail_share_text",
            activity.title.isEmpty ? String(localized: "explore_pin_untitled") : activity.title,
            DateTimeFormatters.sessionDayClockRange(activity.startsAt, activity.endsAt, locale: locale),
            activity.venueName ?? activity.address ?? ""
        )
    }

    /** 有坐标就用系统地图打开（Android `geo:` intent）。 */
    private func openMap(_ activity: any ActivityTypeFullActivity) -> (() -> Void)? {
        guard let lat = activity.locationLat, let lng = activity.locationLng else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lng)"),
            URLQueryItem(name: "q", value: activity.venueName ?? activity.title),
        ]
        guard let url = components.url else { return nil }
        return { openURL(url) }
    }

    private func openProfile(_ profileId: String) {
        shell?.push(NearRoute.socialProfile(profileId: profileId))
    }

    private func openChecklist() {
        shell?.push(NearRoute.checklist(activityType: model.activityType, activityId: model.activityId))
    }
}

/** 加到系统日历的预填内容（Android `addToCalendar`）。 */
func calendarDraft(_ activity: any ActivityTypeFullActivity) -> CalendarDraft? {
    CalendarDraft(
        title: activity.title,
        startsAt: activity.startsAt,
        endsAt: activity.endsAt,
        location: activity.venueName ?? activity.address,
        notes: activity.description
    )
}
