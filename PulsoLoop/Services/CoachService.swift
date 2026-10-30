import PulsoLinkCore

/** [CoachService.myVenues] 的上限；服务端最多给 200。 */
private let myVenuesLookupLimit = 100

/** 教练门面（Android `CoachService`）：写操作后经 [VenueEventBus] 让球馆相关页面重拉。 */
struct CoachService: Sendable {
    let repository: CoachRepository
    let eventBus: VenueEventBus
    let profileStore: ProfileStore

    /** 当前社区身份有没有教练角色（教练面板入口）。 */
    var isCoach: Bool { profileStore.current.value?.communityRoles.contains(.coach) == true }

    func myProfile() async throws -> CoachProfile { try await repository.getMyProfile() }

    func saveMyProfile(_ body: SaveCoachProfileRequest) async throws -> CoachProfile {
        try await mutate { try await repository.saveMyProfile(body) }
    }

    func myServices() async throws -> [CoachingService] { try await repository.listMyServices() }
    func createService(_ body: SaveCoachingServiceRequest) async throws -> String { try await mutate { try await repository.createService(body) } }
    func updateService(_ serviceId: String, _ body: SaveCoachingServiceRequest) async throws { try await mutate { try await repository.updateService(serviceId, body) } }
    func archiveService(_ serviceId: String) async throws { try await mutate { try await repository.archiveService(serviceId) } }

    /** 读一次（一个教练只在几家球馆），比如查和某家球馆的合作。 */
    func myVenues(_ statuses: [VenueCoachStatus]?) async throws -> ListWithTotal<VenueCoach> {
        try await repository.listMyVenues(statuses: statuses, offset: 0, limit: myVenuesLookupLimit)
    }

    @MainActor
    func pageMyVenues() -> PagedList<VenueCoach, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listMyVenues(statuses: nil, offset: offset, limit: limit)
        }
    }

    func applyToVenue(_ venueId: String, message: String?) async throws -> String { try await mutate { try await repository.applyToVenue(venueId, message: message) } }
    func answerAsCoach(_ venueCoachId: String, accept: Bool) async throws { try await mutate { try await repository.answerAsCoach(venueCoachId, accept: accept) } }
    func leaveAsCoach(_ venueCoachId: String) async throws { try await mutate { try await repository.leaveAsCoach(venueCoachId) } }

    /** 我从 [from] 开始教的课。 */
    @MainActor
    func pageCoachSessions(from: String) -> PagedList<CoachingSession, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listCoachSessions(CoachingSessionsRequest(limit: limit, offset: offset, from: from))
        }
    }

    func createSessions(_ body: CreateCoachingSessionsRequest) async throws -> CreateCoachingSessionsResult { try await mutate { try await repository.createSessions(body) } }
    func requestCourt(_ sessionId: String, method: CourtBookingPaymentMethod) async throws { try await mutate { try await repository.requestCourt(sessionId, method: method) } }
    func addParticipants(_ sessionId: String, profileIds: [String]) async throws { try await mutate { try await repository.addParticipants(sessionId, profileIds: profileIds) } }

    func markParticipantPaid(_ sessionId: String, profileId: String, method: CoachingPaymentMethod?, waive: Bool) async throws {
        try await mutate { try await repository.markParticipantPaid(sessionId, profileId: profileId, method: method, waive: waive) }
    }

    func cancelSession(_ sessionId: String, reason: String?) async throws { try await mutate { try await repository.cancelSession(sessionId, reason: reason) } }
    func completeSession(_ sessionId: String) async throws { try await mutate { try await repository.completeSession(sessionId) } }
    func coachPage(_ profileId: String) async throws -> CoachProfile { try await repository.getCoachPage(profileId) }
    func venueCoaches(_ venueId: String) async throws -> [VenueCoach] { try await repository.listVenueCoaches(venueId) }
    func venueCoachPolicy(_ venueId: String) async throws -> CoachPolicy { try await repository.getVenueCoachPolicy(venueId) }

    @MainActor
    func pageMySessions() -> PagedList<CoachingSession, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listMySessions(CoachingSessionsRequest(limit: limit, offset: offset))
        }
    }

    func session(_ sessionId: String) async throws -> CoachingSession { try await repository.getSession(sessionId) }
    func answerInvite(_ sessionId: String, accept: Bool) async throws { try await mutate { try await repository.answerInvite(sessionId, accept: accept) } }
    func pay(_ sessionId: String) async throws -> CoachingPayment { try await repository.pay(sessionId) }

    func invalidate() {
        eventBus.invalidate()
    }

    private func mutate<T>(_ block: () async throws -> T) async throws -> T {
        let out = try await block()
        eventBus.invalidate()
        return out
    }
}

/** 球馆课程门面（Android `CourseService`，学员侧 + 教练授课 / 报酬账）。 */
struct CourseService: Sendable {
    let repository: CourseRepository
    let eventBus: VenueEventBus

    func venueCourses(_ venueId: String) async throws -> [Course] { try await repository.listVenueCourses(venueId) }
    func course(_ courseId: String) async throws -> Course { try await repository.getCourse(courseId) }

    /** 平台付款要等付款面板完成后再失效。 */
    func enroll(_ courseId: String, method: CoursePaymentMethod) async throws -> EnrollResult {
        let out = try await repository.enroll(courseId, method: method)
        if out.clientSecret == nil { eventBus.invalidate() }
        return out
    }

    @MainActor
    func pageMyEnrollments() -> PagedList<CourseEnrollment, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.listMyEnrollments(offset: offset, limit: limit)
        }
    }

    func cancelMyEnrollment(_ enrollmentId: String) async throws {
        try await repository.cancelMyEnrollment(enrollmentId)
        eventBus.invalidate()
    }

    func myTeaching(from: String, to: String) async throws -> [CourseSession] { try await repository.listMyTeaching(from: from, to: to) }

    func myCompensations(_ statuses: [CoachCompensationStatus]?, limit: Int) async throws -> CoachCompensationPage {
        try await repository.listMyCompensations(statuses: statuses, limit: limit)
    }

    func invalidate() {
        eventBus.invalidate()
    }
}
