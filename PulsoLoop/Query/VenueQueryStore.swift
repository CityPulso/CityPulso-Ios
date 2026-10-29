import PulsoLinkCore

/** 我的订场的一次有上限的读取（日程、活动中心）；订场页本身分页。 */
struct MyCourtBookingsKey: Hashable, Sendable {
    var accountId: String
    var profileId: String
    var upcoming: Bool
    var limit: Int
}

/**
 * 球馆读接口的缓存（对应 Android `VenueQueryStore`）。任何球馆写操作（[VenueEventBus]）全部失效。
 * 目前有活动中心要用的「我的订场」；球馆搜索 / 详情 / 订场在第 8 组接上。
 */
final class VenueQueryStore: LogoutClearable {
    let badmintonMyBookings: MemoryQuery<MyCourtBookingsKey, ListWithTotal<BadmintonMyCourtBooking>>
    let tennisMyBookings: MemoryQuery<MyCourtBookingsKey, ListWithTotal<TennisMyCourtBooking>>
    let pickleballMyBookings: MemoryQuery<MyCourtBookingsKey, ListWithTotal<PickleballMyCourtBooking>>

    init(badminton: BadmintonEntryAPI, tennis: TennisEntryAPI, pickleball: PickleballEntryAPI, eventBus: VenueEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        badmintonMyBookings = MemoryQuery(invalidates: invalidates) { key in
            try await badminton.listMyBadmintonCourtBookings(BadmintonMyCourtBookingsRequest(limit: key.limit, upcoming: key.upcoming))
                .dataOrThrow("ListMyBadmintonCourtBookings")
        }
        tennisMyBookings = MemoryQuery(invalidates: invalidates) { key in
            try await tennis.listMyTennisCourtBookings(TennisMyCourtBookingsRequest(limit: key.limit, upcoming: key.upcoming))
                .dataOrThrow("ListMyTennisCourtBookings")
        }
        pickleballMyBookings = MemoryQuery(invalidates: invalidates) { key in
            try await pickleball.listMyPickleballCourtBookings(PickleballMyCourtBookingsRequest(limit: key.limit, upcoming: key.upcoming))
                .dataOrThrow("ListMyPickleballCourtBookings")
        }
    }

    /** 某运动的我的订场，换成统一的行。 */
    func myBookings(_ sport: VenueSport, _ key: MyCourtBookingsKey) -> AsyncStream<QueryResponse<[CourtBookingRowUi]>> {
        switch sport {
        case .badminton: badmintonMyBookings.stream(key).mapResponses { $0.items.map(CourtBookingRowUi.init) }
        case .tennis: tennisMyBookings.stream(key).mapResponses { $0.items.map(CourtBookingRowUi.init) }
        case .pickleball: pickleballMyBookings.stream(key).mapResponses { $0.items.map(CourtBookingRowUi.init) }
        }
    }

    func onLogout() async throws {
        await badmintonMyBookings.clear()
        await tennisMyBookings.clear()
        await pickleballMyBookings.clear()
    }
}
