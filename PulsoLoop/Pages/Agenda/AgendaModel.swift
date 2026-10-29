import Factory
import Foundation
import PulsoLinkCore
import SwiftUI

/** 日程行点开去哪：某运动的活动，或某运动的订场。 */
enum AgendaTarget: Hashable, Sendable {
    case event(LoopSport)
    case booking(VenueSport)
}

struct AgendaItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let place: String
    let startsAt: String
    let endsAt: String
    let start: Date
    let sport: LoopSport
    let coverImageId: String?
    /** 订到的场地，逗号分隔；活动是 nil。 */
    let courtLabel: String?
    let target: AgendaTarget

    var route: LoopRoute {
        switch target {
        case let .event(sport): .event(sport: sport, eventId: id)
        case let .booking(sport): .courtBooking(sport: sport, bookingId: id)
        }
    }
}

/**
 * 日程（对应 Android `AgendaViewModel`）：各运动未结束的报名 + 即将到来和最近的订场，按开始时间排。
 */
@MainActor
@Observable
final class AgendaModel {
    private static let agendaLimit = 100
    private static let pastLimit = 10
    private nonisolated static let agendaStatuses: Set<RegistrationStatus> = [.participating, .pendingExit, .waitlisted, .awaitingPayment]
    private nonisolated static let droppedBookingStatuses: Set<CourtBookingStatus> = [.canceled, .expired]

    var tab: AgendaTab = .events
    private(set) var isPulser = false
    private var events: [LoopSport: Loadable<[AgendaItem]>] = [:]
    private var bookings: [VenueSport: Loadable<[AgendaItem]>] = [:]
    private var pastBookings: [VenueSport: Loadable<[AgendaItem]>] = [:]

    @ObservationIgnored @Injected(\.loopSportServices) private var services
    @ObservationIgnored @Injected(\.venueQueryStore) private var venueQueries
    @ObservationIgnored @Injected(\.venueEventBus) private var venueEventBus
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    /** 所有运动的活动，最早的在前。 */
    var eventItems: Loadable<[AgendaItem]> { Self.merge(Array(events.values)) }
    var bookingItems: Loadable<[AgendaItem]> { Self.merge(Array(bookings.values)) }
    /** 已结束的订场，最近的在前。 */
    var pastBookingItems: [AgendaItem] { (Self.merge(Array(pastBookings.values)).data ?? []).reversed() }

    /** 活动按本地日期分组，日期和行都是最早的在前。 */
    var eventsByDay: [(day: Date, items: [AgendaItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: eventItems.data ?? []) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        let session = sessionStore.state.value
        guard !session.currentAccountId.isEmpty, !session.currentProfileId.isEmpty else { return }
        isPulser = profileStore.current.value?.isPulser == true
        let query = SportRegistrationsQuery(
            accountId: session.currentAccountId, profileId: session.currentProfileId, limit: Self.agendaLimit, includeEnded: false
        )
        var operations: [@MainActor () async -> Void] = []
        for (sport, service) in services {
            let stream = service.myRegistrations(query)
            operations.append {
                for await response in stream {
                    self.events[sport] = (self.events[sport] ?? Loadable()).reduce(response.map(Self.eventItems))
                }
            }
        }
        for sport in VenueSport.allCases {
            let upcoming = venueQueries.myBookings(sport, MyCourtBookingsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, upcoming: true, limit: Self.agendaLimit))
            let past = venueQueries.myBookings(sport, MyCourtBookingsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, upcoming: false, limit: Self.pastLimit))
            operations.append {
                for await response in upcoming {
                    self.bookings[sport] = (self.bookings[sport] ?? Loadable()).reduce(response.map { Self.bookingItems($0, sport: sport, past: false) })
                }
            }
            operations.append {
                for await response in past {
                    self.pastBookings[sport] = (self.pastBookings[sport] ?? Loadable()).reduce(response.map { Self.bookingItems($0, sport: sport, past: true) })
                }
            }
        }
        await concurrently(operations)
    }

    /** 下拉刷新：订场页签让球馆查询重拉，活动页签强制重拉各运动的报名。 */
    func refresh() async {
        let session = sessionStore.state.value
        guard !session.currentAccountId.isEmpty, !session.currentProfileId.isEmpty else { return }
        if tab == .courts {
            venueEventBus.invalidate()
            return
        }
        let query = SportRegistrationsQuery(
            accountId: session.currentAccountId, profileId: session.currentProfileId, limit: Self.agendaLimit, includeEnded: false
        )
        for (sport, service) in services {
            do {
                try await service.freshMyRegistrations(query)
            } catch {
                events[sport] = (events[sport] ?? Loadable()).failed(error)
            }
        }
    }

    /** 正在加载的、第一个错误、所有已回答的运动的行（Android `mergeAgenda`）。 */
    private static func merge(_ parts: [Loadable<[AgendaItem]>]) -> Loadable<[AgendaItem]> {
        let answered = parts.compactMap(\.data)
        return Loadable(
            data: answered.isEmpty ? nil : answered.flatMap { $0 }.sorted { ($0.start, $0.id) < ($1.start, $1.id) },
            isLoading: parts.isEmpty || parts.contains(where: \.isLoading),
            error: parts.compactMap(\.error).first
        )
    }

    private nonisolated static func eventItems(_ rows: [any SportRegistrationItem]) -> [AgendaItem] {
        rows.filter { agendaStatuses.contains($0.registrationStatus) && !isEndedLike(isEnded: $0.isEnded, endsAt: $0.endsAt) }
            .map { row in
                AgendaItem(
                    id: row.id,
                    title: row.title?.isEmpty == false ? row.title : nil,
                    place: [row.venueName, row.address].compactMap { $0 }.first { !$0.isEmpty } ?? "—",
                    startsAt: row.startsAt,
                    endsAt: row.endsAt,
                    start: DateTimeFormatters.parseInstant(row.startsAt) ?? .distantFuture,
                    sport: row.sport,
                    coverImageId: row.coverImageId,
                    courtLabel: nil,
                    target: .event(row.sport)
                )
            }
    }

    /** 取消 / 过期的不是计划，去掉；「即将到来」也去掉已经结束的。 */
    private nonisolated static func bookingItems(_ rows: [CourtBookingRowUi], sport: VenueSport, past: Bool) -> [AgendaItem] {
        rows.filter { !droppedBookingStatuses.contains($0.status) && (past || !isEndedLike(isEnded: false, endsAt: $0.endsAt)) }
            .map { booking in
                AgendaItem(
                    id: booking.id,
                    title: booking.venueName.isEmpty ? nil : booking.venueName,
                    place: booking.venueAddress.isEmpty ? "—" : booking.venueAddress,
                    startsAt: booking.startsAt,
                    endsAt: booking.endsAt,
                    start: DateTimeFormatters.parseInstant(booking.startsAt) ?? .distantFuture,
                    sport: sport.loopSport,
                    coverImageId: booking.venueCoverImageId,
                    courtLabel: booking.courtNames.isEmpty ? nil : booking.courtNames.joined(separator: ", "),
                    target: .booking(sport)
                )
            }
    }
}

extension QueryResponse {
    /** 换个值的形状，loading / error 原样。 */
    func map<R: Sendable>(_ transform: (Output) -> R) -> QueryResponse<R> {
        switch self {
        case .loading: .loading
        case let .data(value): .data(transform(value))
        case let .error(error): .error(error)
        }
    }
}
