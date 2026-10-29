import Foundation

/** Auth 域门面：仓储调用 + 成功后的跨模块事件（pages / stores 不直接碰 [AuthRepository]）。 */
public struct AuthService: Sendable {
    private let auth: AuthRepository
    private let authEventBus: AuthEventBus

    public init(auth: AuthRepository, authEventBus: AuthEventBus) {
        self.auth = auth
        self.authEventBus = authEventBus
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

    public func updatePreference(kind: ProfileKind, preference: String) async throws {
        try await auth.updatePreference(kind: kind, preference: preference)
        authEventBus.emit(.updateAccountSuccess)
    }
}
