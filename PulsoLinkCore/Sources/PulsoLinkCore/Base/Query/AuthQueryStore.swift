import Foundation

/**
 * auth 域的查询缓存（对应 Android `AuthQueryStore`）。key 带账号 id，换账号不会读到上一个账号的缓存；
 * 退出登录时全部清掉。
 */
public final class AuthQueryStore: LogoutClearable {
    /** key = 账号 id。 */
    public let emails: MemoryQuery<String, [EmailItem]>

    public init(auth: AuthRepository, authEventBus: AuthEventBus) {
        emails = MemoryQuery(invalidates: {
            authEventBus.signals { event in
                switch event {
                case .invalidateEmails, .logout: true
                default: false
                }
            }
        }) { _ in
            try await auth.listEmails().items
        }
    }

    public func onLogout() async throws {
        await emails.clear()
    }
}
