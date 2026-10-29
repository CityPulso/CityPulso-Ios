import Foundation
import PulsoLinkCore

/** 与后端 `RemindCooldown` / WEB `REMIND_COOLDOWN_MS` 一致：10 分钟。 */
private let remindCooldown: TimeInterval = 10 * 60

/** 一场活动的收款清单（各运动 `<Sport>PaymentChecklistResponse` 的共同部分）。 */
struct EventChecklist: Sendable {
    let hostProfileId: String
    let isAllSettled: Bool
    let items: [EventChecklistEntry]
}

/** 清单里的一位参与者（`<Sport>PaymentChecklistItem`）。 */
struct EventChecklistEntry: Sendable, Identifiable {
    let id: String
    let profileId: String
    let paid: Bool
    let lastRemindedAt: String?
    let displayName: String?
    let avatarImageId: String?

    /** 未付、且距上次提醒满 10 分钟（与后端一致）才能催。 */
    func canRemind(now: Date = .now) -> Bool {
        guard !paid else { return false }
        guard let raw = lastRemindedAt, !raw.isEmpty, let at = DateTimeFormatters.parseInstant(raw) else { return true }
        return now.timeIntervalSince(at) >= remindCooldown
    }
}

/** 收款清单的读写（每个运动的 Service 遵守）。 */
protocol SportChecklistService: Sendable {
    func checklist(eventId: String) -> AsyncStream<QueryResponse<EventChecklist>>
    func markChecklistItem(itemId: String, paid: Bool) async throws
    func settleChecklist(eventId: String) async throws
    func remindChecklist(eventId: String, itemIds: [String]) async throws
}
