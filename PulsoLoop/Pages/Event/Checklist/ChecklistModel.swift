import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动收款清单（Android `<Sport>EventChecklistViewModel`，对齐 WEB Payment Checklist）：加载、全部结清、单条标记、催缴。
 * 只催未付的；已付的后端会跳过，界面也不显示提醒。
 */
@MainActor
@Observable
final class ChecklistModel {
    private(set) var page = Loadable<EventChecklist>()
    private(set) var isActionInProgress = false

    @ObservationIgnored private let service: any LoopSportService
    @ObservationIgnored private let eventId: String
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(sport: LoopSport, eventId: String) {
        self.eventId = eventId
        service = Container.shared.loopSportServices()[sport]!
    }

    var items: [EventChecklistEntry] { page.data?.items ?? [] }
    var paidCount: Int { items.count { $0.paid } }
    var unpaidCount: Int { items.count - paidCount }

    var isHost: Bool {
        guard let me = profileStore.current.value?.profileId else { return false }
        return me == page.data?.hostProfileId
    }

    /** 未付且过了冷却、可以催的条目。 */
    var remindableIds: [String] { items.filter { $0.canRemind() }.map(\.id) }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        for await response in service.checklist(eventId: eventId) {
            page = page.reduce(response)
        }
    }

    func refresh() {
        service.invalidate()
    }

    func togglePaid(_ item: EventChecklistEntry) async {
        guard isHost else { return }
        await runAction(fallback: "checklist_action_failed") {
            try await self.service.markChecklistItem(itemId: item.id, paid: !item.paid)
        }
    }

    func settleAll() async {
        guard isHost else { return }
        await runAction(fallback: "checklist_action_failed") { try await self.service.settleChecklist(eventId: self.eventId) }
    }

    func remind(_ item: EventChecklistEntry) async {
        guard isHost, item.canRemind() else { return }
        await remind([item.id])
    }

    /** 催所有可以催的未付项（WEB `remindAll`）。 */
    func remindAll() async {
        guard isHost else { return }
        await remind(remindableIds)
    }

    private func remind(_ itemIds: [String]) async {
        guard !itemIds.isEmpty else { return }
        await runAction(fallback: "checklist_remind_failed") {
            try await self.service.remindChecklist(eventId: self.eventId, itemIds: itemIds)
        }
    }

    private func runAction(fallback: String.LocalizationValue, _ block: @escaping @MainActor () async throws -> Void) async {
        guard !isActionInProgress else { return }
        isActionInProgress = true
        defer { isActionInProgress = false }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: fallback)
        }
    }
}
