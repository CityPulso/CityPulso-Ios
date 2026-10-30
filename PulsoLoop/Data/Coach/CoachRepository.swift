import PulsoLinkCore

/** 教练仓储（Android `CoachRepository`）：教练资料、服务、合作球馆、私教课，以及学员侧的私教课。 */
struct CoachRepository: Sendable {
    let api: CoachAPI

    func getMyProfile() async throws -> CoachProfile { try await api.getMyProfile().dataOrThrow("GetMyCoachProfile") }
    func saveMyProfile(_ body: SaveCoachProfileRequest) async throws -> CoachProfile { try await api.saveMyProfile(body).dataOrThrow("SaveMyCoachProfile") }
    func listMyServices() async throws -> [CoachingService] { try await api.listMyServices().dataOrThrow("ListMyCoachingServices") }
    func createService(_ body: SaveCoachingServiceRequest) async throws -> String { try await api.createService(body).dataOrThrow("CreateCoachingService").id }
    func updateService(_ serviceId: String, _ body: SaveCoachingServiceRequest) async throws { try await api.updateService(serviceId: serviceId, body) }
    func archiveService(_ serviceId: String) async throws { try await api.archiveService(serviceId: serviceId) }

    func listMyVenues(statuses: [VenueCoachStatus]?, offset: Int, limit: Int) async throws -> ListWithTotal<VenueCoach> {
        try await api.listMyVenues(CoachVenuesRequest(limit: limit, offset: offset, statuses: statuses)).dataOrThrow("ListMyCoachVenues")
    }

    func applyToVenue(_ venueId: String, message: String?) async throws -> String {
        try await api.applyToVenue(ApplyToVenueRequest(venueId: venueId, message: message)).dataOrThrow("ApplyToVenue").id
    }

    func answerAsCoach(_ venueCoachId: String, accept: Bool) async throws { try await api.answerAsCoach(venueCoachId: venueCoachId, AnswerRequest(accept: accept)) }
    func leaveAsCoach(_ venueCoachId: String) async throws { try await api.leaveAsCoach(venueCoachId: venueCoachId) }
    func listCoachSessions(_ body: CoachingSessionsRequest) async throws -> ListWithTotal<CoachingSession> { try await api.listCoachSessions(body).dataOrThrow("ListCoachSessions") }
    func createSessions(_ body: CreateCoachingSessionsRequest) async throws -> CreateCoachingSessionsResult { try await api.createSessions(body).dataOrThrow("CreateCoachingSessions") }
    func requestCourt(_ sessionId: String, method: CourtBookingPaymentMethod) async throws { try await api.requestCourt(sessionId: sessionId, CourtRequestBody(paymentMethod: method)) }
    func addParticipants(_ sessionId: String, profileIds: [String]) async throws { try await api.addParticipants(sessionId: sessionId, ParticipantsRequest(profileIds: profileIds)) }

    func markParticipantPaid(_ sessionId: String, profileId: String, method: CoachingPaymentMethod?, waive: Bool) async throws {
        try await api.markParticipantPaid(sessionId: sessionId, profileId: profileId, MarkPaidRequest(method: method, waive: waive))
    }

    func cancelSession(_ sessionId: String, reason: String?) async throws { try await api.cancelSession(sessionId: sessionId, ReasonRequest(reason: reason)) }
    func completeSession(_ sessionId: String) async throws { try await api.completeSession(sessionId: sessionId) }
    func getCoachPage(_ profileId: String) async throws -> CoachProfile { try await api.getCoachPage(profileId: profileId).dataOrThrow("GetCoachPage") }
    func listVenueCoaches(_ venueId: String) async throws -> [VenueCoach] { try await api.listVenueCoaches(venueId: venueId).dataOrThrow("ListVenueCoaches") }
    func getVenueCoachPolicy(_ venueId: String) async throws -> CoachPolicy { try await api.getVenueCoachPolicy(venueId: venueId).dataOrThrow("GetVenueCoachPolicy") }
    func listMySessions(_ body: CoachingSessionsRequest) async throws -> ListWithTotal<CoachingSession> { try await api.listMySessions(body).dataOrThrow("ListMyCoachingSessions") }
    func getSession(_ sessionId: String) async throws -> CoachingSession { try await api.getSession(sessionId: sessionId).dataOrThrow("GetCoachingSession") }
    func answerInvite(_ sessionId: String, accept: Bool) async throws { try await api.answerInvite(sessionId: sessionId, AnswerRequest(accept: accept)) }
    func pay(_ sessionId: String) async throws -> CoachingPayment { try await api.pay(sessionId: sessionId).dataOrThrow("PayCoachingSession") }
}

/** 球馆课程仓储（Android `CourseRepository`）：学员侧报名，教练侧授课和报酬账。 */
struct CourseRepository: Sendable {
    let api: CourseAPI

    func listVenueCourses(_ venueId: String) async throws -> [Course] { try await api.listVenueCourses(venueId: venueId).dataOrThrow("ListVenueCourses") }
    func getCourse(_ courseId: String) async throws -> Course { try await api.getCourse(courseId: courseId).dataOrThrow("GetCourse") }
    func enroll(_ courseId: String, method: CoursePaymentMethod) async throws -> EnrollResult { try await api.enroll(courseId: courseId, EnrollRequest(paymentMethod: method)).dataOrThrow("EnrollCourse") }

    func listMyEnrollments(offset: Int, limit: Int) async throws -> ListWithTotal<CourseEnrollment> {
        try await api.listMyEnrollments(CourseEnrollmentsRequest(limit: limit, offset: offset)).dataOrThrow("ListMyCourseEnrollments")
    }

    func cancelMyEnrollment(_ enrollmentId: String) async throws { try await api.cancelMyEnrollment(enrollmentId: enrollmentId) }
    func listMyTeaching(from: String, to: String) async throws -> [CourseSession] { try await api.listMyTeaching(TimeRangeRequest(from: from, to: to)).dataOrThrow("ListMyCoachTeaching") }

    func listMyCompensations(statuses: [CoachCompensationStatus]?, limit: Int) async throws -> CoachCompensationPage {
        try await api.listMyCompensations(CoachCompensationsRequest(limit: limit, statuses: statuses)).dataOrThrow("ListMyCoachCompensations")
    }
}
