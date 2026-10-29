import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 邮箱管理（对应 Android `EmailAddressesViewModel`）；列表本身由 [EmailListModel] 跟着失效事件重拉。 */
@MainActor
@Observable
final class EmailAddressesModel {
    let list = EmailListModel()

    var newEmail = ""
    private(set) var isAdding = false
    /** 正在操作的那一行（显示进度、禁用按钮）。 */
    private(set) var busyEmailId: String?

    var editing: EmailItem?
    var editValue = ""
    var verifying: EmailItem?
    var verifyCode = ""
    var confirmPrimary: EmailItem?
    var confirmDelete: EmailItem?

    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.communitySignIn) private var signIn

    func addEmail() async {
        let email = Self.normalized(newEmail)
        guard Self.isValid(email) else { return PulsoMessageCenter.shared.error("account_security_email_invalid") }
        isAdding = true
        defer { isAdding = false }
        do {
            _ = try await authService.createEmail(email)
            newEmail = ""
            PulsoMessageCenter.shared.success("account_security_email_added")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "account_security_email_add_failed")
        }
    }

    func startEdit(_ email: EmailItem) {
        guard !email.isPrimary else { return }
        editValue = email.email
        editing = email
    }

    func saveEdit() async {
        guard let email = editing, !email.isPrimary else { return }
        let value = Self.normalized(editValue)
        guard Self.isValid(value) else { return PulsoMessageCenter.shared.error("account_security_email_invalid") }
        editing = nil
        await mutate(email.id, success: "account_security_email_updated") {
            try await self.authService.updateEmail(emailId: email.id, email: value)
        }
    }

    func startVerify(_ email: EmailItem) {
        verifyCode = ""
        verifying = email
    }

    func sendCode() async {
        guard let email = verifying else { return }
        await mutate(email.id, success: "account_security_code_sent") {
            try await self.authService.sendEmailVerificationCode(emailId: email.id, lang: self.signIn.language)
        }
    }

    func verify() async {
        guard let email = verifying else { return }
        guard verifyCode.count == 6 else { return PulsoMessageCenter.shared.error("account_security_code_invalid") }
        let code = verifyCode
        if await mutate(email.id, success: "account_security_email_verified", {
            try await self.authService.verifyEmail(emailId: email.id, verificationCode: code)
        }) {
            verifying = nil
        }
    }

    func setPrimary(_ email: EmailItem) async {
        guard email.verifiedAt != nil, !email.isPrimary else { return }
        await mutate(email.id, success: "account_security_primary_set") {
            try await self.authService.setPrimaryEmail(emailId: email.id)
        }
    }

    func delete(_ email: EmailItem) async {
        guard !email.isPrimary else { return }
        if email.verifiedAt != nil, list.verifiedCount <= 1 {
            return PulsoMessageCenter.shared.error("account_security_cannot_delete_last_verified")
        }
        await mutate(email.id, success: "account_security_email_deleted") {
            try await self.authService.deleteEmail(emailId: email.id)
        }
    }

    /** 一次邮箱操作：这一行显示进度，成功一句、失败按规则提示。 */
    @discardableResult
    private func mutate(_ id: String, success: String.LocalizationValue, _ work: () async throws -> Void) async -> Bool {
        busyEmailId = id
        defer { busyEmailId = nil }
        do {
            try await work()
            PulsoMessageCenter.shared.success(success)
            return true
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "account_security_email_action_failed")
            return false
        }
    }

    private static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func isValid(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }
}
