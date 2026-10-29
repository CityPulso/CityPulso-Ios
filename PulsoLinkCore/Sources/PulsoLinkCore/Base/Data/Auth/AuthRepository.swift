import Foundation

/** 当前会话所选身份的账号聚合（后端按 token 里的 profile_id 投影成单个身份）。 */
public enum CurrentFullAccountInformation: Sendable, Hashable {
    case community(FullAccountInformationWithCommunityProfile)
    case organization(FullAccountInformationWithOrganizationProfile)
    case authority(FullAccountInformationWithAuthorityProfile)
}

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

    public func loginWithApple(_ body: LoginWithAppleRequest) async throws -> LoginWithEmailResponse {
        try await publicAPI.loginWithApple(body).dataOrThrow("LoginWithApple")
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

    /* ------------------------------ 账号 / 身份 ------------------------------ */

    public func getCurrentFullAccountInformationWithProfile(kind: ProfileKind) async throws -> CurrentFullAccountInformation {
        switch kind {
        case .community:
            .community(try await protectedAPI.getFullAccountInformationWithCommunityProfile()
                .dataOrThrow("GetCurrentFullAccountInformationWithProfile"))
        case .organization:
            .organization(try await protectedAPI.getFullAccountInformationWithOrganizationProfile()
                .dataOrThrow("GetCurrentFullAccountInformationWithProfile"))
        case .authority:
            .authority(try await protectedAPI.getFullAccountInformationWithAuthorityProfile()
                .dataOrThrow("GetCurrentFullAccountInformationWithProfile"))
        }
    }

    public func patchProfile(kind: ProfileKind, _ body: PatchProfileRequest) async throws {
        try await protectedAPI.patchProfile(kind: kind, body)
    }

    public func confirmProfileBackgrounds(kind: ProfileKind, _ body: ConfirmProfileBackgroundsRequest) async throws {
        try await protectedAPI.confirmProfileBackgrounds(kind: kind, body)
    }

    public func listProfiles(kind: ProfileKind, limit: Int? = nil, offset: Int? = nil) async throws -> ProfileItemsByKind {
        switch kind {
        case .community:
            .community(try await protectedAPI.listCommunityProfiles(limit: limit, offset: offset).dataOrThrow("ListProfiles"))
        case .organization:
            .organization(try await protectedAPI.listOrganizationProfiles(limit: limit, offset: offset).dataOrThrow("ListProfiles"))
        case .authority:
            .authority(try await protectedAPI.listAuthorityProfiles(limit: limit, offset: offset).dataOrThrow("ListProfiles"))
        }
    }

    public func lookupProfiles(_ body: LookupProfilesRequest) async throws -> [LookupProfileItem] {
        try await protectedAPI.lookupProfiles(body).dataOrThrow("LookupProfiles").items
    }

    public func updateCitypulsoId(_ body: UpdateCitypulsoIdRequest) async throws {
        try await protectedAPI.updateCitypulsoId(body)
    }

    public func getPublicProfileCard(profileId: String) async throws -> CommunityProfileItem {
        try await protectedAPI.getPublicProfileCard(profileId: profileId).dataOrThrow("GetPublicProfileCard")
    }

    /* ------------------------------ 申请 ------------------------------ */

    public func submitCommunityRoleApplication(_ body: SubmitCommunityRoleApplicationRequest) async throws {
        try await protectedAPI.submitCommunityRoleApplication(body)
    }

    /** 没申请过时 data 为空，返回 nil。 */
    public func getMyCommunityRoleApplication(role: AuthCommunityRole) async throws -> CommunityRoleApplicationItem? {
        try await protectedAPI.getMyCommunityRoleApplication(role: role).data
    }

    /* ------------------------------ 邮箱 / 密码 ------------------------------ */

    public func listEmails() async throws -> ListWithTotal<EmailItem> {
        try await protectedAPI.listEmails().dataOrThrow("ListEmails")
    }

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

/** 按档位区分的身份列表（对应 Android / WEB `ProfileItemsByKind`）。 */
public enum ProfileItemsByKind: Sendable {
    case community(ListWithTotal<CommunityProfileItem>)
    case organization(ListWithTotal<OrganizationProfileItem>)
    case authority(ListWithTotal<AuthorityProfileItem>)
}
