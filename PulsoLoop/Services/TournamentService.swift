import PulsoLinkCore

/** 赛事门面（社区端，Android `TournamentService`）：写操作后经 [VenueEventBus] 通知刷新。 */
struct TournamentService: Sendable {
    let repository: TournamentRepository
    let eventBus: VenueEventBus

    private static let myEntriesInTournament = 20

    func tournament(_ id: String) async throws -> TournamentDetail {
        try await repository.tournament(id)
    }

    func bracket(_ id: String) async throws -> TournamentBracket {
        try await repository.bracket(id)
    }

    func nearby(latitude: Double, longitude: Double, radiusM: Double) async throws -> [TournamentPin] {
        try await repository.nearby(latitude: latitude, longitude: longitude, radiusM: radiusM)
    }

    /** 赛事页：公开赛事，可以搜索、只看一个运动。 */
    @MainActor
    func pagePublic(search: String?, sport: TournamentSport?) -> PagedList<TournamentItem, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.publicList(offset: offset, limit: limit, search: search, sport: sport)
        }
    }

    /** 球馆页上已发布或进行中的赛事（其余服务端不返回）。 */
    @MainActor
    func pageAtVenue(_ venueId: String) -> PagedList<VenueTournament, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.atVenue(venueId, offset: offset, limit: limit)
        }
    }

    func register(divisionId: String, name: String?, teammates: [String], method: TournamentPaymentMethod) async throws -> TournamentEntryChange {
        let change = try await repository.register(divisionId: divisionId, RegisterTournamentRequest(name: name, teammates: teammates, paymentMethod: method))
        if change.clientSecret == nil { eventBus.invalidate() }
        return change
    }

    @MainActor
    func pageMyEntries() -> PagedList<TournamentEntry, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.myEntries(offset: offset, limit: limit)
        }
    }

    /** 我在这场赛事里的报名（任何组别）；赛事页底部栏和组别卡用。 */
    func myEntriesIn(_ tournamentId: String) async throws -> [TournamentEntry] {
        try await repository.myEntries(offset: 0, limit: Self.myEntriesInTournament, tournamentId: tournamentId).items
    }

    func answer(entryId: String, accept: Bool) async throws {
        try await repository.answer(entryId: entryId, accept: accept)
        eventBus.invalidate()
    }

    func pay(entryId: String) async throws -> TournamentEntryChange {
        try await repository.pay(entryId: entryId)
    }

    func withdraw(entryId: String) async throws {
        try await repository.withdraw(entryId: entryId)
        eventBus.invalidate()
    }

    @MainActor
    func pageMyPrizes() -> PagedList<TournamentGrant, Int> {
        let repository = repository
        return .offset(invalidates: { eventBus.signals { _ in true } }) { offset, limit in
            try await repository.myPrizes(offset: offset, limit: limit)
        }
    }

    func invalidate() {
        eventBus.invalidate()
    }
}
