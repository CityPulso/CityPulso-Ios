import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 当前账号的邮箱列表（账户安全、邮箱、修改密码三页共用）：走 [AuthQueryStore] 的邮箱缓存：
 * 每次邮箱变化（增删改、验证、设主邮箱）自动重拉，与 Android `AuthQueryStore.streamEmails` 一致。
 */
@MainActor
@Observable
final class EmailListModel {
    private(set) var state = Loadable<[EmailItem]>()

    @ObservationIgnored @Injected(\.authQueryStore) private var queries
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore

    var emails: [EmailItem]? { state.data }
    var loadError: UiError? { state.data == nil ? state.error : nil }

    var primaryEmail: EmailItem? {
        emails.flatMap { list in list.first(where: \.isPrimary) ?? list.first }
    }

    /** 收验证码的已验证邮箱（主邮箱优先）。 */
    var verifiedPrimaryEmail: String? {
        emails.flatMap { list in
            (list.first { $0.isPrimary && $0.verifiedAt != nil } ?? list.first { $0.verifiedAt != nil })?.email
        }
    }

    var verifiedCount: Int {
        emails?.count { $0.verifiedAt != nil } ?? 0
    }

    /** 订阅邮箱查询：有缓存先显示，邮箱一变就重拉；页面消失时随 `.task` 取消。 */
    func observe() async {
        for await response in queries.emails.stream(sessionStore.state.value.currentAccountId) {
            state = state.reduce(response)
        }
    }

    /** 失败后重试。 */
    func load() async {
        do {
            state = Loadable(data: try await queries.emails.fresh(sessionStore.state.value.currentAccountId), isLoading: false)
        } catch {
            state = state.failed(error)
        }
    }
}
