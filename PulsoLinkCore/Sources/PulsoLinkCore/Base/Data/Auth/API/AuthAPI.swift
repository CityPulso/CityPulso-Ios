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

    public func loginWithApple(_ body: LoginWithAppleRequest) async throws -> DataResponse<LoginWithEmailResponse> {
        try await client.request(.post, "auth/login/with-apple", body: body)
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

    /* ------------------------------ 账号 / 身份 ------------------------------ */

    public func getFullAccountInformationWithCommunityProfile(authorization: String? = nil) async throws
        -> DataResponse<FullAccountInformationWithCommunityProfile> {
        try await client.request(.get, "auth/me/full-account-information-with-community-profile", headers: authorization.map { ["Authorization": $0] } ?? [:])
    }

    public func getFullAccountInformationWithOrganizationProfile(authorization: String? = nil) async throws
        -> DataResponse<FullAccountInformationWithOrganizationProfile> {
        try await client.request(.get, "auth/me/full-account-information-with-organization-profile", headers: authorization.map { ["Authorization": $0] } ?? [:])
    }

    public func getFullAccountInformationWithAuthorityProfile(authorization: String? = nil) async throws
        -> DataResponse<FullAccountInformationWithAuthorityProfile> {
        try await client.request(.get, "auth/me/full-account-information-with-authority-profile", headers: authorization.map { ["Authorization": $0] } ?? [:])
    }

    public func patchProfile(kind: ProfileKind, _ body: PatchProfileRequest) async throws {
        try await client.send(.patch, "auth/me/\(kind.rawValue)-profile", body: body)
    }

    public func confirmProfileBackgrounds(kind: ProfileKind, _ body: ConfirmProfileBackgroundsRequest) async throws {
        try await client.send(.put, "auth/me/\(kind.rawValue)-profile/backgrounds", body: body)
    }

    public func listCommunityProfiles(limit: Int? = nil, offset: Int? = nil) async throws
        -> DataResponse<ListWithTotal<CommunityProfileItem>> {
        try await client.request(.get, "auth/me/profiles", query: ["limit": limit.map(String.init), "offset": offset.map(String.init)])
    }

    public func listOrganizationProfiles(limit: Int? = nil, offset: Int? = nil) async throws
        -> DataResponse<ListWithTotal<OrganizationProfileItem>> {
        try await client.request(.get, "auth/me/organization-profiles", query: ["limit": limit.map(String.init), "offset": offset.map(String.init)])
    }

    public func listAuthorityProfiles(limit: Int? = nil, offset: Int? = nil) async throws
        -> DataResponse<ListWithTotal<AuthorityProfileItem>> {
        try await client.request(.get, "auth/me/authority-profiles", query: ["limit": limit.map(String.init), "offset": offset.map(String.init)])
    }

    public func lookupProfiles(_ body: LookupProfilesRequest) async throws -> DataResponse<LookupProfilesResponse> {
        try await client.request(.post, "auth/profiles/lookup", body: body)
    }

    public func updateCitypulsoId(_ body: UpdateCitypulsoIdRequest) async throws {
        try await client.send(.put, "auth/me/citypulso-id", body: body)
    }

    public func getPublicProfileCard(profileId: String) async throws -> DataResponse<CommunityProfileItem> {
        try await client.request(.get, "auth/me/profiles/\(profileId)/public-card")
    }

    /* ------------------------------ 申请 ------------------------------ */

    public func submitCommunityRoleApplication(_ body: SubmitCommunityRoleApplicationRequest) async throws {
        try await client.send(.post, "auth/me/community-role-applications", body: body)
    }

    public func getMyCommunityRoleApplication(role: AuthCommunityRole) async throws -> DataResponse<CommunityRoleApplicationItem> {
        try await client.request(.get, "auth/me/community-role-applications/\(role.rawValue)")
    }

    /* ------------------------------ 邮箱 / 密码 ------------------------------ */

    public func listEmails(limit: Int? = nil, offset: Int? = nil) async throws -> DataResponse<ListWithTotal<EmailItem>> {
        try await client.request(.get, "auth/me/emails", query: ["limit": limit.map(String.init), "offset": offset.map(String.init)])
    }

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
