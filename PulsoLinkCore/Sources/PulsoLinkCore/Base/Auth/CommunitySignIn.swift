import Foundation

/**
 * 每种登录方式（邮箱登录、邮箱注册、Google、Apple）共用的收尾（对应 Android Loop / Near 的 `CommunitySignIn`）。
 *
 * 手机端只用 community 身份，并且总是记住登录：拿到 step-1 token 后直接选中账号的 community 身份，
 * 先用新身份的 token 读到档案、把服务端偏好套到本地，再把身份写进会话（写进去 App 就打开了，打开时已经是这个身份）。
 * 中途失败不留半截会话，下次从头来。
 */
public struct CommunitySignIn: Sendable {
    private let authService: AuthService
    private let sessionStore: AuthSessionStore
    private let deviceIdProvider: DeviceIdProvider
    private let authEventBus: AuthEventBus
    private let profileBootstrap: ProfileBootstrap
    private let preferenceBootstrap: PreferenceBootstrap
    private let preferenceService: PreferenceService
    private let sessionTerminator: SessionTerminator
    private let config: PulsoCoreConfig

    public init(
        authService: AuthService,
        sessionStore: AuthSessionStore,
        deviceIdProvider: DeviceIdProvider,
        authEventBus: AuthEventBus,
        profileBootstrap: ProfileBootstrap,
        preferenceBootstrap: PreferenceBootstrap,
        preferenceService: PreferenceService,
        sessionTerminator: SessionTerminator,
        config: PulsoCoreConfig
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.deviceIdProvider = deviceIdProvider
        self.authEventBus = authEventBus
        self.profileBootstrap = profileBootstrap
        self.preferenceBootstrap = preferenceBootstrap
        self.preferenceService = preferenceService
        self.sessionTerminator = sessionTerminator
        self.config = config
    }

    public func deviceId() async -> String {
        await deviceIdProvider.ensureDeviceId()
    }

    /** 当前偏好里的语言：新账号的语言、验证码邮件的语言都用它。 */
    public var language: PulsoLanguage {
        preferenceService.preference.value.language
    }

    public func loginWithEmail(email: String, password: String) async throws {
        let deviceId = await deviceId()
        let response = try await authService.loginWithEmail(
            LoginWithEmailRequest(email: email, password: password, deviceId: deviceId)
        )
        try await complete(response, deviceId: deviceId)
    }

    /** [idToken] 是 Google 签发给 web client（`/auth/env` 的 google_client_id）的 ID token。 */
    public func loginWithGoogle(idToken: String) async throws {
        let deviceId = await deviceId()
        let response = try await authService.loginWithGoogle(
            LoginWithGoogleRequest(
                idToken: idToken,
                deviceId: deviceId,
                signupPlatform: config.signupPlatform,
                lang: language,
                clientOs: .ios
            )
        )
        try await complete(response, deviceId: deviceId)
    }

    /** [identityToken] 是「通过 Apple 登录」给的 identity token；[displayName] 只有第一次授权才有。 */
    public func loginWithApple(identityToken: String, displayName: String?) async throws {
        let deviceId = await deviceId()
        let response = try await authService.loginWithApple(
            LoginWithAppleRequest(
                identityToken: identityToken,
                displayName: displayName,
                deviceId: deviceId,
                signupPlatform: config.signupPlatform,
                lang: language,
                clientOs: .ios
            )
        )
        try await complete(response, deviceId: deviceId)
    }

    public func sendSignupCode(email: String) async throws {
        try await authService.sendVerificationCode(SendVerificationCodeRequest(email: email, lang: language))
    }

    /**
     * 邮箱注册。注册会顺带建好 community 身份，响应里有 profileId 时直接进 App。
     * - Returns: false 表示后端没给 profileId，需要再去登录页登录一次。
     */
    public func signupWithEmail(email: String, password: String, verificationCode: String) async throws -> Bool {
        let response = try await authService.signupWithEmail(
            SignupWithEmailRequest(
                email: email,
                password: password,
                verificationCode: verificationCode,
                lang: language,
                deviceId: await deviceId(),
                signupPlatform: config.signupPlatform,
                clientOs: .ios
            )
        )
        guard let profileId = response.profileId else { return false }
        try await cleanOnFailure {
            try await enter(accountId: response.accountId, tokens: TokensResponse(accessToken: response.accessToken, refreshToken: response.refreshToken), profileId: profileId)
        }
        return true
    }

    /** step-1 响应（邮箱登录、Google、Apple）→ 完整的 community 会话。 */
    public func complete(_ response: LoginWithEmailResponse, deviceId: String) async throws {
        try await cleanOnFailure {
            sessionStore.clearProfileSelection()
            // step-1 token 是账号级的（还没选身份），会话不完整，App 不会打开。
            sessionStore.setTokens(TokensResponse(accessToken: response.accessToken, refreshToken: response.refreshToken), rememberMe: true)
            sessionStore.setCurrentAccountId(response.accountId)
            sessionStore.setIsAuthValid(true)

            guard let community = response.profiles.first(where: { $0.kind == .community }) else {
                throw MissingCommunityProfileError()
            }
            let selected = try await authService.selectProfile(
                SelectProfileRequest(profileId: community.profileId, kind: .community, deviceId: deviceId)
            )
            let tokens = TokensResponse(accessToken: selected.accessToken, refreshToken: selected.refreshToken)
            // 选身份会在服务端作废 step-1 的 refresh token：马上换成新的一对（仍没有身份，App 还不打开），
            // 读档案期间就不会有人拿作废的票去刷新。
            sessionStore.setTokens(tokens, rememberMe: true)
            try await enter(accountId: selected.accountId, tokens: tokens, profileId: selected.profileId)
        }
    }

    /**
     * 身份一写进会话 App 就打开，所以先用它自己的 token 读到档案、套上偏好：打开时就是这个身份，
     * 不会停在一个等不来的加载上。
     */
    private func enter(accountId: String, tokens: TokensResponse, profileId: String) async throws {
        let info = try await authService.getCurrentFullAccountInformationWithProfile(kind: .community, accessToken: tokens.accessToken)
        await profileBootstrap.adopt(info, profileId: profileId, kind: .community)
        _ = preferenceBootstrap.applyFromProfile(info)
        sessionStore.setTokens(tokens, rememberMe: true)
        sessionStore.setCurrentAccountId(accountId)
        sessionStore.setCurrentProfileId(profileId)
        sessionStore.setCurrentProfileKind(.community)
        authEventBus.emit(.loginSuccess(accountId: accountId))
    }

    /** 登录做到一半失败不留东西：结束半截会话（账号 token、没有身份），错误交给页面。 */
    private func cleanOnFailure(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            if !sessionStore.state.value.isCompleteSession {
                let terminator = sessionTerminator
                await Task { await terminator.terminate(.signInFailed) }.value
            }
            throw error
        }
    }
}

/** 账号还没有 community 身份（比如还在建），这里没有可以登录的。 */
public struct MissingCommunityProfileError: Error, Sendable {}
