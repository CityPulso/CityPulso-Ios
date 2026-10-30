import Factory
import Foundation
import PulsoLinkCore
import SwiftUI

/** 一场在这栋建筑办的活动（任何运动）。 */
struct HostedEventRow: Identifiable {
    let item: any SportEventItem

    var id: String { "\(item.sport.rawValue):\(item.id)" }
}

/**
 * 一栋建筑里办的活动，所有运动合在一起按开始时间排（Android 球馆 / 建筑详情里的 `streamEvents(buildingId)` +
 * `mergeSportAnswers`）：即将开始 / 历史两种。
 */
@MainActor
@Observable
final class BuildingEvents {
    private(set) var filter = BuildingSessionFilter.upcoming
    private(set) var events = Loadable<[HostedEventRow]>(isLoading: false)

    @ObservationIgnored private let sportServices = Container.shared.loopSportServices()
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var buildingId = ""
    @ObservationIgnored private var session = AuthSession.loggedOut

    func select(_ next: BuildingSessionFilter) {
        filter = next
        reload()
    }

    /** 建筑或身份变了就重拉；没变什么都不做。 */
    func load(buildingId: String, session: AuthSession) {
        self.buildingId = buildingId
        self.session = session
        reload()
    }

    func cancel() {
        task?.cancel()
    }

    private func reload() {
        let next = "\(buildingId)|\(filter)|\(session.currentProfileId)"
        guard next != key else { return }
        key = next
        task?.cancel()
        guard !buildingId.isEmpty else {
            events = Loadable(isLoading: false)
            return
        }
        events = Loadable(data: events.data, isLoading: true)
        let endedOnly = filter == .history
        let streams = LoopSport.allCases.compactMap { sport in
            sportServices[sport].map { (sport, $0.buildingEvents(accountId: session.currentAccountId, profileId: session.currentProfileId, buildingId: buildingId, endedOnly: endedOnly)) }
        }
        var answers: [LoopSport: QueryResponse<[any SportEventItem]>] = [:]
        let total = streams.count
        task = Task {
            await concurrently(streams.map { sport, stream in
                {
                    for await response in stream {
                        answers[sport] = response
                        self.merge(answers, total: total)
                    }
                }
            })
        }
    }

    private func merge(_ answers: [LoopSport: QueryResponse<[any SportEventItem]>], total: Int) {
        var rows: [any SportEventItem] = []
        var firstError: UiError?
        var pending = total - answers.count
        for answer in answers.values {
            switch answer {
            case let .data(items): rows += items
            case let .error(error): firstError = firstError ?? error
            case .loading: pending += 1
            }
        }
        rows.sort { ($0.startsAt, $0.id) < ($1.startsAt, $1.id) }
        events = Loadable(data: rows.map(HostedEventRow.init), isLoading: pending > 0 && rows.isEmpty, error: rows.isEmpty && pending == 0 ? firstError : nil)
    }
}
