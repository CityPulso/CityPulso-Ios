import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 我的课程（Android `MyCoursesViewModel`）：报名分页；取消后经球馆事件重拉。 */
@MainActor
@Observable
final class MyCoursesModel {
    let enrollments: PagedList<CourseEnrollment, Int>
    private(set) var busyId: String?

    @ObservationIgnored @Injected(\.courseService) private var courseService

    init() {
        enrollments = Container.shared.courseService().pageMyEnrollments()
    }

    func cancel(_ enrollmentId: String) async {
        busyId = enrollmentId
        defer { busyId = nil }
        do {
            try await courseService.cancelMyEnrollment(enrollmentId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "program_action_failed")
        }
    }
}

/** 我的课程（Android `MyCoursesScreen`）：每条报名一行，待付款 / 待确认的可以取消。 */
struct MyCoursesView: View {
    @State private var model = MyCoursesModel()
    @State private var canceling: CourseEnrollment?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.locale) private var locale

    var body: some View {
        ProgramList(list: model.enrollments, emptyTitle: "my_courses_empty", emptyBody: "my_courses_empty_body") {
            Button("my_courses_browse") { shell?.open(.explore) }.buttonStyle(.glassProminent)
        } row: { enrollment in
            NavigationLink(value: LoopRoute.course(courseId: enrollment.courseId)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: enrollment.courseTitle).font(.headline)
                    Text(verbatim: [
                        String(localized: enrollment.status.labelResource),
                        enrollment.venueName,
                        formatMoney(enrollment.amount, currency: enrollment.currency, locale: locale),
                        enrollment.nextSessionAt.map { localizedFormat("my_courses_next", DateTimeFormatters.monthDayTime($0, locale: locale) ?? "") },
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .swipeActions {
                if enrollment.status == .pending || enrollment.status == .awaitingPayment {
                    Button("my_courses_cancel", role: .destructive) { canceling = enrollment }
                }
            }
            .overlay(alignment: .trailing) { if model.busyId == enrollment.id { ProgressView() } }
        }
        .navigationTitle("my_courses_title")
        .confirmationDialog("my_courses_cancel_title", isPresented: Binding(get: { canceling != nil }, set: { if !$0 { canceling = nil } }), titleVisibility: .visible, presenting: canceling) { enrollment in
            Button("my_courses_cancel", role: .destructive) { Task { await model.cancel(enrollment.id) } }
        } message: { _ in
            Text("my_courses_cancel_body")
        }
    }
}

/** 我的私教课（Android `MyCoachingViewModel`）：课分页；我是教练时还有教练面板入口。 */
@MainActor
@Observable
final class MyCoachingModel {
    let sessions: PagedList<CoachingSession, Int>
    private(set) var busyId: String?
    private(set) var isCoach = false
    private(set) var profileId = ""

    @ObservationIgnored @Injected(\.coachService) private var coachService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore

    init() {
        sessions = Container.shared.coachService().pageMySessions()
    }

    func observe() async {
        await concurrently([
            { await self.sessions.observe() },
            {
                for await info in self.profileStore.current.values() {
                    self.isCoach = info?.communityRoles.contains(.coach) == true
                    self.profileId = info?.profileId ?? ""
                }
            },
        ])
    }

    func answer(_ sessionId: String, accept: Bool) async {
        await act(sessionId) { try await self.coachService.answerInvite(sessionId, accept: accept) }
    }

    /** 平台付款给教练：拿到付款意图后弹付款面板。 */
    func pay(_ sessionId: String) async {
        await act(sessionId) {
            let payment = try await self.coachService.pay(sessionId)
            guard let secret = payment.clientSecret else { return }
            switch await ConnectedPaymentSheet.present(ConnectedPaymentIntent(publishableKey: payment.publishableKey, providerAccountId: payment.providerAccountId, clientSecret: secret)) {
            case .completed: self.coachService.invalidate()
            case .canceled: break
            case let .failed(message): PulsoMessageCenter.shared.error(text: message)
            }
        }
    }

    private func act(_ id: String, _ block: @escaping () async throws -> Void) async {
        busyId = id
        defer { busyId = nil }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "program_action_failed")
        }
    }
}

/** 我的私教课（Android `MyCoachingScreen`）：时间、进度、教练 / 球馆 / 场地 / 价格；被邀请可接受或拒绝，接受后可付款。 */
struct MyCoachingView: View {
    @State private var model = MyCoachingModel()
    @Environment(\.locale) private var locale

    var body: some View {
        ProgramList(list: model.sessions, observe: false, emptyTitle: "my_coaching_empty", emptyBody: "my_coaching_empty_body") {
            EmptyView()
        } header: {
            if model.isCoach {
                NavigationLink(value: LoopRoute.coachPanel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("my_coaching_coach_panel").font(.headline)
                        Text("my_coaching_coach_panel_hint").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } row: { session in
            sessionRow(session)
        }
        .navigationTitle("my_coaching_title")
        .task { await model.observe() }
    }

    private func sessionRow(_ session: CoachingSession) -> some View {
        let me = (session.participants ?? []).first { $0.profileId == model.profileId }
        let live = session.venueState != .canceled && session.venueState != .completed
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: DateTimeFormatters.monthDayTime(session.startsAt, locale: locale) ?? "").font(.headline)
            Text(verbatim: [
                String(localized: session.venueState.labelResource),
                session.coachDisplayName ?? "",
                session.venueName,
                session.courtName,
                formatMoney(session.priceAmount, currency: session.currency, locale: locale),
            ].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let me {
                Text(verbatim: "\(String(localized: me.status.labelResource)) · \(String(localized: me.paymentStatus.labelResource))").font(.caption)
                if live {
                    HStack {
                        if me.status == .invited {
                            Button("my_coaching_accept") { Task { await model.answer(session.id, accept: true) } }
                                .buttonStyle(.glassProminent)
                            Button("my_coaching_decline") { Task { await model.answer(session.id, accept: false) } }
                                .buttonStyle(.glass)
                        }
                        if me.status == .accepted, me.paymentStatus == .unpaid || me.paymentStatus == .awaitingPayment {
                            Button("my_coaching_pay") { Task { await model.pay(session.id) } }
                                .buttonStyle(.glass)
                        }
                        if model.busyId == session.id { ProgressView() }
                    }
                    .disabled(model.busyId == session.id)
                }
            }
        }
    }
}

/** 「我的课程 / 私教 / 赛事」共用（Android `ProgramListScaffold`）：加载、错误、空状态、分页列表（滑到底取下一页）。 */
struct ProgramList<Item: Identifiable & Sendable, EmptyAction: View, Header: View, Row: View>: View {
    let list: PagedList<Item, Int>
    var observe = true
    let emptyTitle: LocalizedStringKey
    let emptyBody: LocalizedStringKey
    @ViewBuilder let emptyAction: () -> EmptyAction
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Item) -> Row

    init(
        list: PagedList<Item, Int>,
        observe: Bool = true,
        emptyTitle: LocalizedStringKey,
        emptyBody: LocalizedStringKey,
        @ViewBuilder emptyAction: @escaping () -> EmptyAction,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.list = list
        self.observe = observe
        self.emptyTitle = emptyTitle
        self.emptyBody = emptyBody
        self.emptyAction = emptyAction
        self.header = header
        self.row = row
    }

    var body: some View {
        List {
            header()
            if list.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = list.error {
                PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
            } else if list.isEmpty {
                ContentUnavailableView {
                    Text(emptyTitle)
                } description: {
                    Text(emptyBody)
                } actions: {
                    emptyAction()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(list.items) { item in
                    row(item)
                        .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
                }
            }
        }
        .refreshable { await list.refresh() }
        .task { if observe { await list.observe() } }
    }
}
