import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 当前账号的邮箱列表（账户安全、邮箱、修改密码三页共用）：先拉一次，之后每次邮箱变化
 *（增删改、验证、设主邮箱）自动重拉，与 Android 的邮箱查询失效后重取一致。
 */
@MainActor
@Observable
final class EmailListModel {
    private(set) var emails: [EmailItem]?
    private(set) var loadError: UiError?

    @ObservationIgnored @Injected(\.authService) private var authService

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

    /** 跟着邮箱失效事件一直重拉；页面消失时随 `.task` 取消。 */
    func observe() async {
        for await _ in authService.emailInvalidations() {
            await load()
        }
    }

    func load() async {
        do {
            emails = try await authService.listEmails()
            loadError = nil
        } catch {
            loadError = UiError(error)
        }
    }
}
