import Foundation

/** Auth 域门面：仓储调用 + 成功后的跨模块事件（pages / stores 不直接碰 [AuthRepository]）。 */
public struct AuthService: Sendable {
    private let auth: AuthRepository
    private let authEventBus: AuthEventBus

    private let sessionStore: AuthSessionStore

    public init(auth: AuthRepository, authEventBus: AuthEventBus, sessionStore: AuthSessionStore) {
        self.auth = auth
        self.authEventBus = authEventBus
        self.sessionStore = sessionStore
    }

    /* ------------------------------ 登录 / 注册 ------------------------------ */

    public func loginWithEmail(_ body: LoginWithEmailRequest) async throws -> LoginWithEmailResponse {
        try await auth.loginWithEmail(body)
    }

    public func loginWithGoogle(_ body: LoginWithGoogleRequest) async throws -> LoginWithEmailResponse {
        try await auth.loginWithGoogle(body)
    }

    public func loginWithApple(_ body: LoginWithAppleRequest) async throws -> LoginWithEmailResponse {
        try await auth.loginWithApple(body)
    }

    /** Google 登录要的 web client ID（ID token 的 audience，后端用它验 token）。 */
    public func googleClientId() async throws -> String {
        try await auth.getAuthEnv().env.googleClientId
    }

    public func sendVerificationCode(_ body: SendVerificationCodeRequest) async throws {
        try await auth.sendVerificationCode(body)
    }

    public func signupWithEmail(_ body: SignupWithEmailRequest) async throws -> SignupWithEmailResponse {
        try await auth.signupWithEmail(body)
    }

    public func selectProfile(_ body: SelectProfileRequest) async throws -> SelectProfileResponse {
        try await auth.selectProfile(body)
    }

    /* ------------------------------ 账号 / 身份 ------------------------------ */

    public func getCurrentFullAccountInformationWithProfile(kind: ProfileKind) async throws -> CurrentFullAccountInformation {
        try await auth.getCurrentFullAccountInformationWithProfile(kind: kind)
    }

    /* ------------------------------ 邮箱 / 密码 ------------------------------ */

    public func createEmail(_ email: String) async throws -> CreateEmailResponse {
        let response = try await auth.createEmail(CreateEmailRequest(email: email))
        invalidateEmails()
        return response
    }

    public func updateEmail(emailId: String, email: String) async throws {
        try await auth.updateEmail(emailId: emailId, email: email)
        invalidateEmails()
    }

    public func sendEmailVerificationCode(emailId: String, lang: PulsoLanguage) async throws {
        try await auth.sendEmailVerificationCode(emailId: emailId, lang: lang)
    }

    public func verifyEmail(emailId: String, verificationCode: String) async throws {
        try await auth.verifyEmail(emailId: emailId, verificationCode: verificationCode)
        invalidateEmails()
        authEventBus.emit(.updateAccountSuccess)
    }

    public func setPrimaryEmail(emailId: String) async throws {
        try await auth.setPrimaryEmail(emailId: emailId)
        invalidateEmails()
        authEventBus.emit(.updateAccountSuccess)
    }

    public func deleteEmail(emailId: String) async throws {
        try await auth.deleteEmail(emailId: emailId)
        invalidateEmails()
        authEventBus.emit(.updateAccountSuccess)
    }

    public func changePassword(newPassword: String, verificationCode: String) async throws {
        try await auth.changePassword(ChangePasswordRequest(newPassword: newPassword, verificationCode: verificationCode))
    }

    public func sendChangePasswordVerificationCode(lang: PulsoLanguage) async throws {
        try await auth.sendChangePasswordVerificationCode(lang: lang)
    }

    private func invalidateEmails() {
        authEventBus.emit(.invalidateEmails(accountId: sessionStore.state.value.currentAccountId))
    }

    /* ------------------------------ 偏好 ------------------------------ */

    public func updatePreference(kind: ProfileKind, preference: String) async throws {
        try await auth.updatePreference(kind: kind, preference: preference)
        authEventBus.emit(.updateAccountSuccess)
    }
}
