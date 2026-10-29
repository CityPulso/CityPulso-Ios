import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 修改密码（对应 Android `ChangePasswordViewModel`）：新密码 + 确认 + 发到主邮箱的验证码。 */
@MainActor
@Observable
final class ChangePasswordModel {
    let emails = EmailListModel()

    var newPassword = ""
    var confirmPassword = ""
    var verificationCode = ""
    private(set) var sendingCode = false
    private(set) var submitting = false

    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.communitySignIn) private var signIn

    func sendCode() async {
        guard emails.verifiedPrimaryEmail != nil else {
            return PulsoMessageCenter.shared.error("account_security_password_need_primary")
        }
        sendingCode = true
        defer { sendingCode = false }
        do {
            try await authService.sendChangePasswordVerificationCode(lang: signIn.language)
            PulsoMessageCenter.shared.success("account_security_code_sent")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "account_security_send_code_failed")
        }
    }

    func changePassword() async {
        if newPassword.count < SignupModel.minPasswordLength { return PulsoMessageCenter.shared.error("signup_password_too_short") }
        if newPassword != confirmPassword { return PulsoMessageCenter.shared.error("signup_passwords_mismatch") }
        if verificationCode.count != 6 { return PulsoMessageCenter.shared.error("account_security_code_invalid") }
        submitting = true
        defer { submitting = false }
        do {
            try await authService.changePassword(newPassword: newPassword, verificationCode: verificationCode)
            newPassword = ""
            confirmPassword = ""
            verificationCode = ""
            PulsoMessageCenter.shared.success("account_security_password_changed")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "account_security_change_password_failed")
        }
    }
}
