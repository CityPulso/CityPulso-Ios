import Foundation

/** 认证仓储——方法与 WEB `ApiAuthRepository` 逐一对齐（URL_PATHS.AUTH）。 */
public struct AuthRepository: Sendable {
    private let publicAPI: AuthPublicAPI
    private let protectedAPI: AuthProtectedAPI

    public init(publicAPI: AuthPublicAPI, protectedAPI: AuthProtectedAPI) {
        self.publicAPI = publicAPI
        self.protectedAPI = protectedAPI
    }

    /* ------------------------------ 登录 / 注册 / 换票 ------------------------------ */

    public func loginWithEmail(_ body: LoginWithEmailRequest) async throws -> LoginWithEmailResponse {
        try await publicAPI.loginWithEmail(body).dataOrThrow("LoginWithEmail")
    }

    public func loginWithGoogle(_ body: LoginWithGoogleRequest) async throws -> LoginWithEmailResponse {
        try await publicAPI.loginWithGoogle(body).dataOrThrow("LoginWithGoogle")
    }

    public func getAuthEnv() async throws -> AuthEnv {
        try await publicAPI.getAuthEnv().dataOrThrow("GetAuthEnv")
    }

    public func sendVerificationCode(_ body: SendVerificationCodeRequest) async throws {
        try await publicAPI.sendVerificationCode(body)
    }

    public func signupWithEmail(_ body: SignupWithEmailRequest) async throws -> SignupWithEmailResponse {
        try await publicAPI.signupWithEmail(body).dataOrThrow("SignupWithEmail")
    }

    public func refreshTokens(_ body: RefreshTokensRequest) async throws -> TokensResponse {
        try await publicAPI.refreshTokens(body).dataOrThrow("RefreshTokens")
    }

    public func selectProfile(_ body: SelectProfileRequest) async throws -> SelectProfileResponse {
        try await protectedAPI.selectProfile(body).dataOrThrow("SelectProfile")
    }

    /* ------------------------------ 邮箱 / 密码 ------------------------------ */

    public func createEmail(_ body: CreateEmailRequest) async throws -> CreateEmailResponse {
        try await protectedAPI.createEmail(body).dataOrThrow("CreateEmail")
    }

    public func sendEmailVerificationCode(emailId: String, lang: PulsoLanguage? = nil) async throws {
        try await protectedAPI.sendEmailVerificationCode(emailId: emailId, SendEmailVerificationCodeRequest(lang: lang))
    }

    public func verifyEmail(emailId: String, verificationCode: String) async throws {
        try await protectedAPI.verifyEmail(emailId: emailId, VerifyEmailRequest(verificationCode: verificationCode))
    }

    public func updateEmail(emailId: String, email: String) async throws {
        try await protectedAPI.updateEmail(emailId: emailId, UpdateEmailRequest(email: email))
    }

    public func setPrimaryEmail(emailId: String) async throws {
        try await protectedAPI.setPrimaryEmail(emailId: emailId)
    }

    public func deleteEmail(emailId: String) async throws {
        try await protectedAPI.deleteEmail(emailId: emailId)
    }

    public func changePassword(_ body: ChangePasswordRequest) async throws {
        try await protectedAPI.changePassword(body)
    }

    public func sendChangePasswordVerificationCode(lang: PulsoLanguage? = nil) async throws {
        try await protectedAPI.sendChangePasswordVerificationCode(SendChangePasswordVerificationCodeRequest(lang: lang))
    }

    /** [preference] 为 Preference JSON 字符串（与 WEB UpdatePreference 一致）。 */
    public func updatePreference(kind: ProfileKind, preference: String) async throws {
        try await protectedAPI.updatePreference(kind: kind, UpdatePreferenceRequest(preference: preference))
    }
}
