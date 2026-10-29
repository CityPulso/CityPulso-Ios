import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 登录。Near 只有 community 身份：先拿 step-1 账号 token，再选中账号的 community 身份，直接进首页（不选身份）。
 */
@MainActor
@Observable
final class LoginModel {
    var email = "" { didSet { errorText = nil } }
    var password = "" { didSet { errorText = nil } }
    var rememberMe = false
    private(set) var loading = false
    /** 显示在密码框下面。 */
    private(set) var errorText: String?

    @ObservationIgnored @Injected(\.communitySignIn) private var signIn

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !loading
    }

    func submit() async {
        guard canSubmit else { return }
        loading = true
        defer { loading = false }
        do {
            try await signIn.loginWithEmail(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                rememberMe: rememberMe
            )
        } catch {
            errorText = (error as? APIError)?.message ?? String(localized: "login_failed_retry")
        }
    }
}
