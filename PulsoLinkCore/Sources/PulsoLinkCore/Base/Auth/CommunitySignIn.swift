import Foundation

/**
 * 每种登录方式（邮箱登录、邮箱注册、Google、Apple）共用的收尾（对应 Android Loop / Near 的 `CommunitySignIn`）。
 *
 * 手机端只用 community 身份：拿到 step-1 token 后直接选中账号的 community 身份，得到完整会话；
 * 再等档案拉到、把它的服务端偏好套到本地（最多 12 秒，超时先进主界面，偏好随后到）。
 */
public struct CommunitySignIn: Sendable {
    private static let profileReadyTimeout: Double = 12

    private let authService: AuthService
    private let sessionStore: AuthSessionStore
    private let deviceIdProvider: DeviceIdProvider
    private let authEventBus: AuthEventBus
    private let profileBootstrap: ProfileBootstrap
    private let profileStore: ProfileStore
    private let preferenceBootstrap: PreferenceBootstrap
    private let preferenceService: PreferenceService
    private let config: PulsoCoreConfig

    public init(
        authService: AuthService,
        sessionStore: AuthSessionStore,
        deviceIdProvider: DeviceIdProvider,
        authEventBus: AuthEventBus,
        profileBootstrap: ProfileBootstrap,
        profileStore: ProfileStore,
        preferenceBootstrap: PreferenceBootstrap,
        preferenceService: PreferenceService,
        config: PulsoCoreConfig
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.deviceIdProvider = deviceIdProvider
        self.authEventBus = authEventBus
        self.profileBootstrap = profileBootstrap
        self.profileStore = profileStore
        self.preferenceBootstrap = preferenceBootstrap
        self.preferenceService = preferenceService
        self.config = config
    }

    public func deviceId() async -> String {
        await deviceIdProvider.ensureDeviceId()
    }

    /** 当前偏好里的语言：新账号的语言、验证码邮件的语言都用它。 */
    public var language: PulsoLanguage {
        preferenceService.preference.value.language
    }

    public func loginWithEmail(email: String, password: String, rememberMe: Bool) async throws {
        let deviceId = await deviceId()
        let response = try await authService.loginWithEmail(
            LoginWithEmailRequest(email: email, password: password, deviceId: deviceId)
        )
        try await complete(response, rememberMe: rememberMe, deviceId: deviceId)
    }

    /** [idToken] 是 Google 签发给 web client（`/auth/env` 的 google_client_id）的 ID token。 */
    public func loginWithGoogle(idToken: String, rememberMe: Bool) async throws {
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
        try await complete(response, rememberMe: rememberMe, deviceId: deviceId)
    }

    public func sendSignupCode(email: String) async throws {
        try await authService.sendVerificationCode(SendVerificationCodeRequest(email: email, lang: language))
    }

    /**
     * 邮箱注册。注册会顺带建好 community 身份，响应里有 profileId 时直接是完整会话（记住登录）。
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
        sessionStore.setTokens(TokensResponse(accessToken: response.accessToken, refreshToken: response.refreshToken), rememberMe: true)
        sessionStore.setCurrentAccountId(response.accountId)
        sessionStore.setIsAuthValid(true)
        guard let profileId = response.profileId else { return false }
        sessionStore.setCurrentProfileId(profileId)
        sessionStore.setCurrentProfileKind(.community)
        await awaitProfileAndPreferences(profileId)
        return true
    }

    /** step-1 响应（邮箱登录、Google、Apple）→ 完整的 community 会话。 */
    public func complete(_ response: LoginWithEmailResponse, rememberMe: Bool, deviceId: String) async throws {
        sessionStore.clearProfileSelection()
        // step-1 token 只留内存（还没选身份，不落盘）。
        sessionStore.setTokens(
            TokensResponse(accessToken: response.accessToken, refreshToken: response.refreshToken),
            rememberMe: rememberMe
        )
        sessionStore.setCurrentAccountId(response.accountId)
        sessionStore.setIsAuthValid(true)

        guard let community = response.profiles.first(where: { $0.kind == .community }) else {
            throw MissingCommunityProfileError()
        }
        let selected = try await authService.selectProfile(
            SelectProfileRequest(profileId: community.profileId, kind: .community, deviceId: deviceId)
        )
        sessionStore.setTokens(TokensResponse(accessToken: selected.accessToken, refreshToken: selected.refreshToken))
        sessionStore.setCurrentAccountId(selected.accountId)
        sessionStore.setCurrentProfileId(selected.profileId)
        sessionStore.setCurrentProfileKind(.community)
        authEventBus.emit(.loginSuccess(accountId: selected.accountId))
        await awaitProfileAndPreferences(selected.profileId)
    }

    /** 等 [ProfileStore] 拿到 [profileId] 的档案，再把它的服务端偏好套到本地。超时就先进主界面，偏好随后到。 */
    private func awaitProfileAndPreferences(_ profileId: String) async {
        let profileBootstrap = profileBootstrap
        let profileStore = profileStore
        let info = await withTimeoutOrNil(seconds: Self.profileReadyTimeout) { () -> CurrentFullAccountInformation? in
            await profileBootstrap.ensureLoaded()
            for await info in profileStore.current.values() where info?.profileId == profileId {
                return info
            }
            return nil
        }
        if let info = info ?? nil {
            preferenceBootstrap.applyFromProfile(info)
        }
    }
}

/** 每个账号注册时都会建 community 身份；登录响应里没有它说明后端数据不完整。 */
public struct MissingCommunityProfileError: Error, Sendable {}
