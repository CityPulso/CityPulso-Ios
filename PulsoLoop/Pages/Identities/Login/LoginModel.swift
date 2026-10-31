import AuthenticationServices
import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 登录（对应 Android `LoginViewModel`）。Loop 只有 community 身份：先拿 step-1 账号 token，
 * 再选中账号的 community 身份，直接进首页（不选身份）。
 */
@MainActor
@Observable
final class LoginModel {
    var email = "" { didSet { errorText = nil } }
    var password = "" { didSet { errorText = nil } }
    /** Google / Apple 登录进行中（邮箱登录走 [submit]）。 */
    private(set) var loading = false
    /** 邮箱登录按钮的阶段：画完勾才进 App。 */
    let submit = SubmitAction()
    /** 显示在密码框下面。 */
    private(set) var errorText: String?

    @ObservationIgnored @Injected(\.communitySignIn) private var signIn
    @ObservationIgnored @Injected(\.authService) private var authService

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !loading && !submit.phase.busy
    }

    /** 先拿 step-1 账号 token；会话（进 App）等按钮画完勾再建。 */
    func login() async {
        guard canSubmit else { return }
        errorText = nil
        let email = email.trimmingCharacters(in: .whitespaces)
        await submit.run({
            let deviceId = await self.signIn.deviceId()
            let response = try await self.authService.loginWithEmail(LoginWithEmailRequest(email: email, password: self.password, deviceId: deviceId))
            return (response, deviceId)
        }, onFailure: { error in
            self.errorText = signInErrorText(error, fallback: "login_failed_retry")
        }, afterSuccess: { result in
            try await self.signIn.complete(result.0, deviceId: result.1)
        })
    }

    func signInWithGoogle() async {
        await run(fallback: "google_sign_in_failed") {
            let serverClientID = try await self.authService.googleClientId()
            guard let idToken = try await GoogleIdToken.request(serverClientID: serverClientID) else { return }
            try await self.signIn.loginWithGoogle(idToken: idToken)
        }
    }

    func signInWithApple(_ result: Result<ASAuthorization, any Error>) async {
        await run(fallback: "login_failed_retry") {
            guard let apple = try AppleIdToken.from(result) else { return }
            try await self.signIn.loginWithApple(
                identityToken: apple.identityToken,
                displayName: apple.displayName
            )
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
