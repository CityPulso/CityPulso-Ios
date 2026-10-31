import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 课程详情（Android `CourseDetailViewModel`）：课程、授课教练、报名（平台付款走付款面板）。球馆有写操作就重拉。 */
@MainActor
@Observable
final class CourseDetailModel {
    let courseId: String

    private(set) var course = Loadable<Course>()
    private(set) var coaches: [VenueCoach] = []
    var method: CoursePaymentMethod?
    private(set) var enrolling = false
    private(set) var outcome: EnrollOutcome?

    @ObservationIgnored @Injected(\.courseService) private var courseService
    @ObservationIgnored @Injected(\.coachService) private var coachService
    @ObservationIgnored @Injected(\.venueEventBus) private var eventBus
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(courseId: String) {
        self.courseId = courseId
    }

    var methods: [CoursePaymentMethod] {
        guard let course = course.data else { return [] }
        return [
            course.acceptsPlatform ? .platform : nil,
            course.acceptsOffline ? .offline : nil,
            course.acceptsPhone ? .phone : nil,
        ].compactMap { $0 }
    }

    var selectedMethod: CoursePaymentMethod? { method.flatMap { methods.contains($0) ? $0 : nil } ?? methods.first }

    /** 已上线且报名还没截止。 */
    var isOpen: Bool {
        guard let course = course.data, course.status == .published else { return false }
        return DateTimeFormatters.parseInstant(course.enrollmentClosesAt).map { $0 > .now } ?? true
    }

    var isFull: Bool { course.data.map { $0.heldCount >= $0.capacity } ?? false }

    /** 这门课的教练（球馆教练里挑出授课的）。 */
    var teaching: [VenueCoach] {
        let ids = Set((course.data?.coaches ?? []).map(\.coachProfileId))
        return coaches.filter { ids.contains($0.coachProfileId) }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        await load()
        for await _ in eventBus.signals(where: { _ in true }) {
            await load()
        }
    }

    func load() async {
        course.isLoading = true
        do {
            let value = try await courseService.course(courseId)
            course = Loadable(data: value, isLoading: false)
            // 教练是附带信息：拿不到课程照样显示。
            if let coaches = try? await coachService.venueCoaches(value.venueId) { self.coaches = coaches }
        } catch {
            course = Loadable(data: course.data, isLoading: false, error: UiError(error))
        }
    }

    func enroll() async {
        guard let method = selectedMethod, !enrolling else { return }
        enrolling = true
        defer { enrolling = false }
        do {
            let result = try await courseService.enroll(courseId, method: method)
            if let secret = result.clientSecret, let account = result.providerAccountId, let key = result.publishableKey {
                switch await ConnectedPaymentSheet.present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret)) {
                case .completed:
                    outcome = .enrolled
                    courseService.invalidate()
                case .canceled: break
                case let .failed(message): PulsoMessageCenter.shared.error(text: message)
                }
            } else {
                outcome = result.status == .enrolled ? .enrolled : .requested
            }
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "program_action_failed")
        }
    }
}

/** 课程详情（Android `CourseDetailScreen`）：照片、标题和概要、报名卡、授课教练、课表。 */
struct CourseDetailView: View {
    @State private var model: CourseDetailModel
    @Environment(\.locale) private var locale

    init(courseId: String) {
        _model = State(initialValue: CourseDetailModel(courseId: courseId))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.course.data?.title ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        if let course = model.course.data {
            List {
                let gallery = course.images.sorted { $0.sortOrder < $1.sortOrder }.compactMap { model.imageURL($0.imageId) }
                if !gallery.isEmpty {
                    Section {
                        TabView {
                            ForEach(gallery, id: \.self) { PulsoRemoteImage(url: $0) }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: course.title).font(.title2.bold())
                        Text(verbatim: [
                            course.venueName,
                            String(localized: course.level.labelResource),
                            localizedFormat("course_detail_sessions", course.sessionCount),
                            formatMoney(course.priceAmount, currency: course.currency, locale: locale),
                        ].joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let description = course.description, !description.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(verbatim: description).font(.body)
                        }
                    }
                    NavigationLink("course_detail_open_venue", value: LoopRoute.venue(venueId: course.venueId, sheet: nil))
                }
                enrollSection(course)
                if !model.teaching.isEmpty {
                    Section("course_detail_coaches") {
                        ForEach(model.teaching, id: \.id) { coach in
                            NavigationLink(value: LoopRoute.coach(profileId: coach.coachProfileId)) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: coach.displayName ?? coach.coachProfileId)
                                    if let headline = coach.headline { Text(verbatim: headline).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                Section("course_detail_schedule") {
                    let sessions = course.sessions.filter { $0.status != .canceled }
                    if sessions.isEmpty {
                        Text("course_detail_no_sessions").foregroundStyle(.secondary)
                    }
                    ForEach(sessions, id: \.id) { session in
                        Text(verbatim: [
                            DateTimeFormatters.monthDayTime(session.startsAt, locale: locale) ?? "",
                            (session.courts ?? []).map(\.courtName).joined(separator: ", "),
                        ].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }
            }
            .refreshable { await model.load() }
        } else if let error = model.course.error {
            if error.kind == .notFound {
                PulsoEmptyState(Text("course_detail_not_found"), description: Text("course_detail_not_found_body"))
            } else {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func enrollSection(_ course: Course) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: localizedFormat("course_detail_enroll_title", formatMoney(course.priceAmount, currency: course.currency, locale: locale))).font(.headline)
                Text(verbatim: localizedFormat("course_detail_seats", max(0, course.capacity - course.heldCount), course.capacity))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let outcome = model.outcome {
                Text((outcome == .enrolled ? "course_detail_enrolled" : "course_detail_requested") as LocalizedStringKey)
                NavigationLink("course_detail_open_mine", value: LoopRoute.myCourses)
            } else if !model.isOpen {
                Text("course_detail_closed").foregroundStyle(.secondary)
            } else if model.isFull {
                Text("course_detail_full").foregroundStyle(.secondary)
            } else {
                if model.methods.count > 1 {
                    Picker(selection: Binding(get: { model.selectedMethod ?? .platform }, set: { model.method = $0 })) {
                        ForEach(model.methods, id: \.self) { Text($0.labelKey).tag($0) }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                }
                Button {
                    Task { await model.enroll() }
                } label: {
                    if model.enrolling { ProgressView().frame(maxWidth: .infinity) } else { Text("course_detail_enroll").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.pulso())
                .disabled(model.selectedMethod == nil || model.enrolling)
            }
        }
    }
}
