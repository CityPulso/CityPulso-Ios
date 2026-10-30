import PulsoLinkCore

/** 赛事仓储（社区端，Android `TournamentRepository`）。 */
struct TournamentRepository: Sendable {
    let api: TournamentAPI

    func tournament(_ id: String) async throws -> TournamentDetail {
        try await api.getTournament(id: id).dataOrThrow("GetTournament")
    }

    func bracket(_ id: String) async throws -> TournamentBracket {
        try await api.getBracket(id: id).dataOrThrow("GetTournamentBracket")
    }

    func nearby(latitude: Double, longitude: Double, radiusM: Double) async throws -> [TournamentPin] {
        try await api.listNearby(NearbyTournamentsRequest(lat: latitude, lng: longitude, radiusM: radiusM)).dataOrThrow("ListNearbyTournaments")
    }

    func atVenue(_ venueId: String, offset: Int, limit: Int) async throws -> ListWithTotal<VenueTournament> {
        try await api.listAtVenue(venueId: venueId, TournamentPageRequest(limit: limit, offset: offset)).dataOrThrow("ListVenueTournaments")
    }

    func register(divisionId: String, _ body: RegisterTournamentRequest) async throws -> TournamentEntryChange {
        try await api.register(divisionId: divisionId, body).dataOrThrow("RegisterTournamentEntry")
    }

    func publicList(offset: Int, limit: Int, search: String?, sport: TournamentSport?) async throws -> ListWithTotal<TournamentItem> {
        try await api.listPublic(PublicTournamentsRequest(limit: limit, offset: offset, search: search, sport: sport)).dataOrThrow("ListPublicTournaments")
    }

    func myEntries(offset: Int, limit: Int) async throws -> ListWithTotal<TournamentEntry> {
        try await api.listMyEntries(TournamentPageRequest(limit: limit, offset: offset)).dataOrThrow("ListMyTournamentEntries")
    }

    func answer(entryId: String, accept: Bool) async throws {
        try await api.answer(entryId: entryId, AnswerRequest(accept: accept))
    }

    func pay(entryId: String) async throws -> TournamentEntryChange {
        try await api.pay(entryId: entryId).dataOrThrow("PayTournamentEntry")
    }

    func withdraw(entryId: String) async throws {
        try await api.withdraw(entryId: entryId)
    }

    func myPrizes(offset: Int, limit: Int) async throws -> ListWithTotal<TournamentGrant> {
        try await api.listMyPrizes(TournamentPageRequest(limit: limit, offset: offset)).dataOrThrow("ListMyTournamentPrizes")
    }
}
