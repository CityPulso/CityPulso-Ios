import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 登录（对应 Android `LoginViewModel`）。Near 只有 community 身份：先拿 step-1 账号 token，
 * 再选中账号的 community 身份，直接进首页（不选身份）。
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
    @ObservationIgnored @Injected(\.authService) private var authService

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !loading
    }

    func submit() async {
        guard canSubmit else { return }
        await run(fallback: "login_failed_retry") {
            try await self.signIn.loginWithEmail(
                email: self.email.trimmingCharacters(in: .whitespaces),
                password: self.password,
                rememberMe: self.rememberMe
            )
        }
    }

    func signInWithGoogle() async {
        await run(fallback: "google_sign_in_failed") {
            let serverClientID = try await self.authService.googleClientId()
            guard let idToken = try await GoogleIdToken.request(serverClientID: serverClientID) else { return }
            try await self.signIn.loginWithGoogle(idToken: idToken, rememberMe: self.rememberMe)
        }
    }

    private func run(fallback: String.LocalizationValue, _ work: () async throws -> Void) async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            try await work()
        } catch {
            errorText = signInErrorText(error, fallback: fallback)
        }
    }
}
