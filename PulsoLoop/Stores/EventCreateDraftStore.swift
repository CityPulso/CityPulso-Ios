import Foundation
import PulsoLinkCore

/**
 * 发起活动的本地草稿（Android `EventCreateDraftStore`）：存一份，进向导时问要不要接着填；退出登录时清掉。
 * 读不了的旧草稿当作没有。
 */
final class EventCreateDraftStore: LogoutClearable {
    private static let key = "loop-event-create-draft"

    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var draft: CreateDraft? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(CreateDraft.self, from: $0) }
    }

    func save(_ draft: CreateDraft) {
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    func onLogout() async throws {
        clear()
    }
}

/** 没发出去的发起表单，设置页「清除本地数据」的草稿一行。 */
struct CreateDraftDataSource: LocalDataSource {
    let kind = LocalDataKind.drafts
    let store: EventCreateDraftStore

    func usage() async throws -> LocalDataUsage {
        LocalDataUsage(count: store.draft == nil ? 0 : 1, bytes: nil)
    }

    func clear() async throws {
        store.clear()
    }
}
