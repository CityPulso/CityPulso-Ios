import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 注册（对应 Android `SignupViewModel`）：邮箱 + 6 位验证码 + 密码（至少 8 位）+ 确认密码；
 * 验证码 60 秒后才能重发。也可以直接用 Google 注册 / 登录。
 */
@MainActor
@Observable
final class SignupModel {
    static let minPasswordLength = 8
    private static let resendCooldownSeconds = 60

    var email = "" { didSet { errorText = nil } }
    var verificationCode = "" { didSet { errorText = nil } }
    var password = "" { didSet { errorText = nil } }
    var confirmPassword = "" { didSet { errorText = nil } }
    private(set) var sendingCode = false
    /** 剩余冷却秒数；0 表示可以发送。 */
    private(set) var resendCountdown = 0
    private(set) var loading = false
    private(set) var errorText: String?
    private(set) var infoText: String?

    @ObservationIgnored @Injected(\.communitySignIn) private var signIn
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var canSendCode: Bool {
        !trimmedEmail.isEmpty && resendCountdown == 0 && !sendingCode
    }

    var passwordTooShort: Bool {
        !password.isEmpty && password.count < Self.minPasswordLength
    }

    var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    var canSubmit: Bool {
        !trimmedEmail.isEmpty
            && verificationCode.count == 6
            && password.count >= Self.minPasswordLength
            && confirmPassword == password
            && !loading
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    func sendCode() async {
        guard canSendCode else { return }
        sendingCode = true
        errorText = nil
        infoText = nil
        defer { sendingCode = false }
        do {
            try await signIn.sendSignupCode(email: trimmedEmail)
            infoText = String(localized: "signup_code_sent")
            startCountdown()
        } catch {
            errorText = signInErrorText(error, fallback: "signup_send_failed_retry")
        }
    }

    /** - Returns: true 表示后端没直接给完整会话，要去登录页再登录一次。 */
    func submit() async -> Bool {
        guard canSubmit else { return false }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let signedIn = try await signIn.signupWithEmail(
                email: trimmedEmail,
                password: password,
                verificationCode: verificationCode
            )
            if !signedIn { infoText = String(localized: "signup_success_go_login") }
            return !signedIn
        } catch {
            errorText = signInErrorText(error, fallback: "signup_failed_retry")
            return false
        }
    }

    func signInWithGoogle() async {
        loading = true
        errorText = nil
        infoText = nil
        defer { loading = false }
        do {
            let serverClientID = try await authService.googleClientId()
            guard let idToken = try await GoogleIdToken.request(serverClientID: serverClientID) else { return }
            try await signIn.loginWithGoogle(idToken: idToken, rememberMe: true)
        } catch {
            errorText = signInErrorText(error, fallback: "google_sign_in_failed")
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        resendCountdown = Self.resendCooldownSeconds
        countdownTask = Task { [weak self] in
            while let self, self.resendCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.resendCountdown -= 1
            }
        }
    }
}
