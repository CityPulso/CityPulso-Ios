import Factory
import Foundation
import PulsoLinkCore
import SwiftUI

/** 日程行点开去哪：某活动类型的活动，或某活动类型的订场。 */
enum AgendaTarget: Hashable, Sendable {
    case activity(NearActivityKind)
    case booking(VenueActivityType)
}

struct AgendaItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let place: String
    let startsAt: String
    let endsAt: String
    let start: Date
    let activityType: NearActivityKind
    let coverImageId: String?
    /** 订到的场地，逗号分隔；活动是 nil。 */
    let spaceLabel: String?
    let target: AgendaTarget

    var route: NearRoute {
        switch target {
        case let .activity(activityType): .activity(activityType: activityType, activityId: id)
        case let .booking(activityType): .spaceBooking(activityType: activityType, bookingId: id)
        }
    }
}

/**
 * 日程（对应 Android `AgendaViewModel`）：各活动类型未结束的报名 + 即将到来和最近的订场，按开始时间排。
 */
@MainActor
@Observable
final class AgendaModel {
    private static let agendaLimit = 100
    private static let pastLimit = 10
    private nonisolated static let agendaStatuses: Set<RegistrationStatus> = [.participating, .pendingExit, .waitlisted, .awaitingPayment]
    private nonisolated static let droppedBookingStatuses: Set<SpaceBookingStatus> = [.canceled, .expired]

    var tab: AgendaTab = .activities
    private(set) var isPulser = false
    private var activities: [NearActivityKind: Loadable<[AgendaItem]>] = [:]
    private var bookings: [VenueActivityType: Loadable<[AgendaItem]>] = [:]
    private var pastBookings: [VenueActivityType: Loadable<[AgendaItem]>] = [:]

    @ObservationIgnored @Injected(\.nearActivityServices) private var services
    @ObservationIgnored @Injected(\.venueBookingServices) private var venueServices
    @ObservationIgnored @Injected(\.venueEventBus) private var venueEventBus
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    /** 所有活动类型的活动，最早的在前。 */
    var activityItems: Loadable<[AgendaItem]> { Self.merge(Array(activities.values)) }
    var bookingItems: Loadable<[AgendaItem]> { Self.merge(Array(bookings.values)) }
    /** 已结束的订场，最近的在前。 */
    var pastBookingItems: [AgendaItem] { (Self.merge(Array(pastBookings.values)).data ?? []).reversed() }

    /** 活动按本地日期分组，日期和行都是最早的在前。 */
    var activitiesByDay: [(day: Date, items: [AgendaItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: activityItems.data ?? []) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        let session = sessionStore.state.value
        guard !session.currentAccountId.isEmpty, !session.currentProfileId.isEmpty else { return }
        isPulser = profileStore.current.value?.isPulser == true
        let query = ActivityTypeRegistrationsQuery(
            accountId: session.currentAccountId, profileId: session.currentProfileId, limit: Self.agendaLimit, includeEnded: false
        )
        var operations: [@MainActor () async -> Void] = []
        for (activityType, service) in services {
            let stream = service.myRegistrations(query)
            operations.append {
                for await response in stream {
                    self.activities[activityType] = (self.activities[activityType] ?? Loadable()).reduce(response.map(Self.activityItems))
                }
            }
        }
        for activityType in VenueActivityType.allCases {
            let upcoming = venueServices[activityType]!.myBookings(MySpaceBookingsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, upcoming: true, limit: Self.agendaLimit))
            let past = venueServices[activityType]!.myBookings(MySpaceBookingsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, upcoming: false, limit: Self.pastLimit))
            operations.append {
                for await response in upcoming {
                    self.bookings[activityType] = (self.bookings[activityType] ?? Loadable()).reduce(response.map { Self.bookingItems($0, activityType: activityType, past: false) })
                }
            }
            operations.append {
                for await response in past {
                    self.pastBookings[activityType] = (self.pastBookings[activityType] ?? Loadable()).reduce(response.map { Self.bookingItems($0, activityType: activityType, past: true) })
                }
            }
        }
        await concurrently(operations)
    }

    /** 下拉刷新：订场页签让门店查询重拉，活动页签强制重拉各活动类型的报名。 */
    func refresh() async {
        let session = sessionStore.state.value
        guard !session.currentAccountId.isEmpty, !session.currentProfileId.isEmpty else { return }
        if tab == .spaces {
            venueEventBus.invalidate()
            return
        }
        let query = ActivityTypeRegistrationsQuery(
            accountId: session.currentAccountId, profileId: session.currentProfileId, limit: Self.agendaLimit, includeEnded: false
        )
        for (activityType, service) in services {
            do {
                try await service.freshMyRegistrations(query)
            } catch {
                activities[activityType] = (activities[activityType] ?? Loadable()).failed(error)
            }
        }
    }

    /** 正在加载的、第一个错误、所有已回答的活动类型的行（Android `mergeAgenda`）。 */
    private static func merge(_ parts: [Loadable<[AgendaItem]>]) -> Loadable<[AgendaItem]> {
        let answered = parts.compactMap(\.data)
        return Loadable(
            data: answered.isEmpty ? nil : answered.flatMap { $0 }.sorted { ($0.start, $0.id) < ($1.start, $1.id) },
            isLoading: parts.isEmpty || parts.contains(where: \.isLoading),
            error: parts.compactMap(\.error).first
        )
    }

    private nonisolated static func activityItems(_ rows: [any ActivityTypeRegistrationItem]) -> [AgendaItem] {
        rows.filter { agendaStatuses.contains($0.registrationStatus) && !isEndedLike(isEnded: $0.isEnded, endsAt: $0.endsAt) }
            .map { row in
                AgendaItem(
                    id: row.id,
                    title: row.title?.isEmpty == false ? row.title : nil,
                    place: [row.venueName, row.address].compactMap { $0 }.first { !$0.isEmpty } ?? "—",
                    startsAt: row.startsAt,
                    endsAt: row.endsAt,
                    start: DateTimeFormatters.parseInstant(row.startsAt) ?? .distantFuture,
                    activityType: row.activityType,
                    coverImageId: row.coverImageId,
                    spaceLabel: nil,
                    target: .activity(row.activityType)
                )
            }
    }

    /** 取消 / 过期的不是计划，去掉；「即将到来」也去掉已经结束的。 */
    private nonisolated static func bookingItems(_ rows: [SpaceBookingRowUi], activityType: VenueActivityType, past: Bool) -> [AgendaItem] {
        // 到店开台还没结束的没有结束时间，算作没结束。
        rows.filter { !droppedBookingStatuses.contains($0.status) && (past || !($0.endsAt.map { isEndedLike(isEnded: false, endsAt: $0) } ?? false)) }
            .map { booking in
                AgendaItem(
                    id: booking.id,
                    title: booking.venueName.isEmpty ? nil : booking.venueName,
                    place: booking.venueAddress.isEmpty ? "—" : booking.venueAddress,
                    startsAt: booking.startsAt,
                    endsAt: booking.endsAt ?? "",
                    start: DateTimeFormatters.parseInstant(booking.startsAt) ?? .distantFuture,
                    activityType: activityType.kind,
                    coverImageId: booking.venueCoverImageId,
                    spaceLabel: booking.spaceNames.isEmpty ? nil : booking.spaceNames.joined(separator: ", "),
                    target: .booking(activityType)
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
