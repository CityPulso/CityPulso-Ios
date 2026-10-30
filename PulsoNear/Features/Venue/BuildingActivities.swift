import Factory
import Foundation
import PulsoLinkCore
import SwiftUI

/** 一场在这栋建筑办的活动（任何活动类型）。 */
struct HostedActivityRow: Identifiable {
    let item: any ActivityItem

    var id: String { "\(item.activityType.rawValue):\(item.id)" }
}

/**
 * 一栋建筑里办的活动，所有活动类型合在一起按开始时间排（Android 门店 / 建筑详情里的 `streamActivities(buildingId)` +
 * `mergeActivityTypeAnswers`）：即将开始 / 历史两种。
 */
@MainActor
@Observable
final class BuildingActivities {
    private(set) var filter = BuildingActivityFilter.upcoming
    private(set) var activities = Loadable<[HostedActivityRow]>(isLoading: false)

    @ObservationIgnored private let activityTypeServices = Container.shared.nearActivityServices()
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var buildingId = ""
    @ObservationIgnored private var session = AuthSession.loggedOut

    func select(_ next: BuildingActivityFilter) {
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
            activities = Loadable(isLoading: false)
            return
        }
        activities = Loadable(data: activities.data, isLoading: true)
        let endedOnly = filter == .history
        let streams = NearActivityKind.allCases.compactMap { activityType in
            activityTypeServices[activityType].map { (activityType, $0.buildingActivities(accountId: session.currentAccountId, profileId: session.currentProfileId, buildingId: buildingId, endedOnly: endedOnly)) }
        }
        var answers: [NearActivityKind: QueryResponse<[any ActivityItem]>] = [:]
        let total = streams.count
        task = Task {
            await concurrently(streams.map { activityType, stream in
                {
                    for await response in stream {
                        answers[activityType] = response
                        self.merge(answers, total: total)
                    }
                }
            })
        }
    }

    private func merge(_ answers: [NearActivityKind: QueryResponse<[any ActivityItem]>], total: Int) {
        var rows: [any ActivityItem] = []
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
        activities = Loadable(data: rows.map(HostedActivityRow.init), isLoading: pending > 0 && rows.isEmpty, error: rows.isEmpty && pending == 0 ? firstError : nil)
    }
}
