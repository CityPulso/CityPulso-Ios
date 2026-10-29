import Foundation

/** 公开认证接口（对应 WEB publicClient 的 AUTH 路径；路径见 PulsoLink-Package `apis/repositories/ip.ts` URL_PATHS.AUTH）。 */
public struct AuthPublicAPI: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func loginWithEmail(_ body: LoginWithEmailRequest) async throws -> DataResponse<LoginWithEmailResponse> {
        try await client.request(.post, "auth/login/with-email", body: body)
    }

    public func loginWithGoogle(_ body: LoginWithGoogleRequest) async throws -> DataResponse<LoginWithEmailResponse> {
        try await client.request(.post, "auth/login/with-google", body: body)
    }

    public func getAuthEnv() async throws -> DataResponse<AuthEnv> {
        try await client.request(.get, "auth/env")
    }

    public func sendVerificationCode(_ body: SendVerificationCodeRequest) async throws {
        try await client.send(.post, "auth/signup/send-code", body: body)
    }

    public func signupWithEmail(_ body: SignupWithEmailRequest) async throws -> DataResponse<SignupWithEmailResponse> {
        try await client.request(.post, "auth/signup/with-email", body: body)
    }

    public func refreshTokens(_ body: RefreshTokensRequest) async throws -> DataResponse<TokensResponse> {
        try await client.request(.post, "auth/refresh", body: body)
    }
}

/** 需 Bearer 的认证接口（对应 WEB protectedClient 的 AUTH.Me 路径）。 */
public struct AuthProtectedAPI: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /* ------------------------------ 会话 ------------------------------ */

    public func selectProfile(_ body: SelectProfileRequest) async throws -> DataResponse<SelectProfileResponse> {
        try await client.request(.post, "auth/me/select-profile", body: body)
    }

    /* ------------------------------ 邮箱 / 密码 ------------------------------ */

    public func createEmail(_ body: CreateEmailRequest) async throws -> DataResponse<CreateEmailResponse> {
        try await client.request(.post, "auth/me/emails", body: body)
    }

    public func sendEmailVerificationCode(emailId: String, _ body: SendEmailVerificationCodeRequest) async throws {
        try await client.send(.post, "auth/me/emails/\(emailId)/send-verification-code", body: body)
    }

    public func verifyEmail(emailId: String, _ body: VerifyEmailRequest) async throws {
        try await client.send(.post, "auth/me/emails/\(emailId)/verify", body: body)
    }

    public func updateEmail(emailId: String, _ body: UpdateEmailRequest) async throws {
        try await client.send(.patch, "auth/me/emails/\(emailId)", body: body)
    }

    public func setPrimaryEmail(emailId: String) async throws {
        try await client.send(.put, "auth/me/emails/\(emailId)/primary")
    }

    public func deleteEmail(emailId: String) async throws {
        try await client.send(.delete, "auth/me/emails/\(emailId)")
    }

    public func changePassword(_ body: ChangePasswordRequest) async throws {
        try await client.send(.put, "auth/me/password", body: body)
    }

    public func sendChangePasswordVerificationCode(_ body: SendChangePasswordVerificationCodeRequest) async throws {
        try await client.send(.post, "auth/me/password/send-verification-code", body: body)
    }

    /* ------------------------------ 偏好 ------------------------------ */

    public func updatePreference(kind: ProfileKind, _ body: UpdatePreferenceRequest) async throws {
        try await client.send(.put, "auth/me/\(kind.rawValue)-profile/preference", body: body)
    }
}
