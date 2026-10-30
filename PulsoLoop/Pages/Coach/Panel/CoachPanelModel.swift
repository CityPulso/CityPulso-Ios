import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI

/** 新建私教课的表单（单次或每周重复）；[sport] 决定可选的场地（Android `SessionDraft`）。 */
struct CoachSessionDraft: Identifiable {
    let id = UUID()
    var venueId: String?
    var sport: VenueSport = .badminton
    var courtId: String?
    var serviceId: String?
    var startsAt = Date.now.addingTimeInterval(86_400)
    var minutes = 60
    var weeks = 1
    var price = ""
    var participants: Set<String> = []
    var requestCourt = true
    var courtMethod: CourtBookingPaymentMethod = .platform
}

/** 一块可选场地（任何运动的场地都映射到这里）。 */
struct CoachCourtOption: Hashable {
    let id: String
    let name: String
}

/** 教练面板（Android `CoachPanelViewModel`）：我教的课、合作球馆、授课报酬、教练资料和服务。教练的写操作都会重拉。 */
@MainActor
@Observable
final class CoachPanelModel {
    static let courtMethods: [CourtBookingPaymentMethod] = [.platform, .offline, .phone]
    static let collectMethods: [CoachingPaymentMethod] = [.cash, .etransfer, .wechat]

    var tab = CoachPanelTab.sessions
    /** 合作中的球馆：新建课次从中选一个。 */
    private(set) var partnerVenues: [VenueCoach] = []
    /** 未来 30 天要教的球馆课程课次。 */
    private(set) var teaching = Loadable<[CourseSession]>()
    private(set) var compensationStatus = CoachCompensationStatus.owed
    private(set) var compensations = Loadable<[CoachCompensation]>()
    private(set) var profile: CoachProfile?
    private(set) var profileLoaded = false
    private(set) var services: [CoachingService] = []
    private(set) var friends: [FriendItem] = []
    private(set) var courts: [CoachCourtOption] = []
    var draft: CoachSessionDraft? { didSet { draftChanged(from: oldValue) } }
    private(set) var created: CreateCoachingSessionsResult?
    private(set) var busy = false
    private(set) var draftError: String?

    /** 从昨天起我教的私教课。 */
    let sessions: PagedList<CoachingSession, Int>
    /** 所有球馆合作（待确认、合作中、已结束）。 */
    let venues: PagedList<VenueCoach, Int>

    @ObservationIgnored @Injected(\.coachService) private var coachService
    @ObservationIgnored @Injected(\.courseService) private var courseService
    @ObservationIgnored @Injected(\.venueSportServices) private var venueSports
    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.venueEventBus) private var eventBus
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init() {
        let service = Container.shared.coachService()
        sessions = service.pageCoachSessions(from: Date.now.addingTimeInterval(-86_400).formatted(.iso8601))
        venues = service.pageMyVenues()
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    func observe() async {
        await concurrently([
            {
                await self.refresh()
                for await _ in self.eventBus.signals(where: { _ in true }) { await self.refresh() }
            },
            { await self.sessions.observe() },
            { await self.venues.observe() },
        ])
    }

    func refresh() async {
        if let page = try? await coachService.myVenues([.active]) { partnerVenues = page.items }
        let now = Date.now
        do {
            teaching = try await Loadable(data: courseService.myTeaching(from: now.formatted(.iso8601), to: now.addingTimeInterval(30 * 86_400).formatted(.iso8601)), isLoading: false)
        } catch {
            teaching = Loadable(data: teaching.data, isLoading: false, error: UiError(error))
        }
        await loadCompensations()
        // 资料页：没有资料表示还没开通，失败时显示开通表单。
        profile = try? await coachService.myProfile()
        services = (try? await coachService.myServices()) ?? []
        profileLoaded = true
    }

    /* ------------------------------ 报酬 ------------------------------ */

    func selectCompensationStatus(_ status: CoachCompensationStatus) async {
        compensationStatus = status
        compensations = Loadable()
        await loadCompensations()
    }

    private func loadCompensations() async {
        let status = compensationStatus
        do {
            let page = try await courseService.myCompensations([status], limit: 100)
            if compensationStatus == status { compensations = Loadable(data: page.items, isLoading: false) }
        } catch {
            if compensationStatus == status { compensations = Loadable(data: compensations.data, isLoading: false, error: UiError(error)) }
        }
    }

    /* ------------------------------ 课次 ------------------------------ */

    func openDraft() {
        let sport = profile?.sports.first ?? .badminton
        created = nil
        draftError = nil
        draft = CoachSessionDraft(venueId: partnerVenues.first?.venueId, sport: sport, serviceId: services.first { $0.sport == sport }?.id)
        loadFriends()
    }

    func closeDraft() {
        draft = nil
        created = nil
        draftError = nil
    }

    private func draftChanged(from old: CoachSessionDraft?) {
        guard let draft, let venueId = draft.venueId else { return }
        if old?.id != draft.id || old?.venueId != draft.venueId || old?.sport != draft.sport { loadCourts(venueId: venueId, sport: draft.sport) }
    }

    /** 球馆这个运动的在用场地；每种运动有自己的场地。 */
    private func loadCourts(venueId: String, sport: VenueSport) {
        courts = []
        if draft?.courtId != nil { draft?.courtId = nil }
        guard let service = venueSports[sport] else { return }
        Task {
            for await response in service.courts(venueId: venueId) {
                if case let .data(list) = response {
                    let options = list.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }.map { CoachCourtOption(id: $0.id, name: $0.name) }
                    guard draft?.venueId == venueId, draft?.sport == sport else { return }
                    courts = options
                    draft?.courtId = options.first?.id
                    return
                }
                if case .error = response { return }
            }
        }
    }

    /** 参加的人可选：没有好友就只有教练自己。 */
    private func loadFriends() {
        let session = sessionStore.state.value
        Task {
            if let list = try? await socialService.getFriends(FriendsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, limit: 100)) {
                friends = list
            }
        }
    }

    func createSessions() async {
        guard let draft, let venueId = draft.venueId, let courtId = draft.courtId else { return }
        draftError = nil
        await act(onError: { self.draftError = UiError($0).text(fallback: String(localized: "program_action_failed")) }) {
            let result = try await self.coachService.createSessions(CreateCoachingSessionsRequest(
                venueId: venueId,
                sport: draft.sport,
                serviceId: draft.serviceId,
                courtId: courtId,
                startsAt: draft.startsAt.formatted(.iso8601),
                endsAt: draft.startsAt.addingTimeInterval(Double(draft.minutes) * 60).formatted(.iso8601),
                weeks: draft.weeks,
                priceAmount: Double(draft.price.trimmingCharacters(in: .whitespaces)),
                participants: Array(draft.participants),
                requestCourt: draft.requestCourt,
                courtPaymentMethod: draft.courtMethod
            ))
            self.created = result
        }
    }

    func requestCourt(_ sessionId: String, method: CourtBookingPaymentMethod) async {
        await act { try await self.coachService.requestCourt(sessionId, method: method) }
    }

    func cancelSession(_ sessionId: String) async {
        await act { try await self.coachService.cancelSession(sessionId, reason: nil) }
    }

    func completeSession(_ sessionId: String) async {
        await act { try await self.coachService.completeSession(sessionId) }
    }

    /** [method] 为 nil 表示免单。 */
    func markPaid(_ sessionId: String, profileId: String, method: CoachingPaymentMethod?) async {
        await act { try await self.coachService.markParticipantPaid(sessionId, profileId: profileId, method: method, waive: method == nil) }
    }

    func participantName(_ profileId: String) -> String {
        friends.first { $0.friendProfileId == profileId }?.profile.displayName ?? String(profileId.prefix(8))
    }

    /* ------------------------------ 球馆 ------------------------------ */

    func answer(_ venueCoachId: String, accept: Bool) async {
        await act { try await self.coachService.answerAsCoach(venueCoachId, accept: accept) }
    }

    func leave(_ venueCoachId: String) async {
        await act { try await self.coachService.leaveAsCoach(venueCoachId) }
    }

    /* ------------------------------ 资料 ------------------------------ */

    func saveProfile(_ body: SaveCoachProfileRequest) async {
        await act { self.profile = try await self.coachService.saveMyProfile(body) }
    }

    /** [existing] 为空时新建，否则整体替换这项服务。 */
    func saveService(_ existing: CoachingService?, sport: VenueSport, title: String, format: CoachingServiceFormat, hourlyPrice: Double) async {
        let body = SaveCoachingServiceRequest(
            sport: sport,
            title: title,
            description: existing?.description,
            format: format,
            maxParticipants: format == .smallGroup ? 6 : format == .oneOnTwo ? 2 : 1,
            hourlyPriceAmount: hourlyPrice,
            sortOrder: existing?.sortOrder ?? 0
        )
        await act {
            if let existing {
                try await self.coachService.updateService(existing.id, body)
            } else {
                _ = try await self.coachService.createService(body)
            }
        }
    }

    func archiveService(_ serviceId: String) async {
        await act { try await self.coachService.archiveService(serviceId) }
    }

    private func act(onError: ((Error) -> Void)? = nil, _ block: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await block()
        } catch {
            if let onError { onError(error) } else { PulsoMessageCenter.shared.error(error, fallback: "program_action_failed") }
        }
    }
}
