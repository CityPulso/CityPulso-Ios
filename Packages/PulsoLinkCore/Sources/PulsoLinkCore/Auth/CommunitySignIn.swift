import Foundation

/**
 * 每种登录方式（邮箱登录、邮箱注册、Google）共用的收尾（对应 Android Loop / Near 的 `CommunitySignIn`）。
 *
 * 手机端只用 community 身份：拿到 step-1 token 后直接选中账号的 community 身份，得到完整会话。
 */
public struct CommunitySignIn: Sendable {
    private let authRepository: AuthRepository
    private let sessionStore: AuthSessionStore
    private let deviceIdProvider: DeviceIdProvider
    private let authEventBus: AuthEventBus

    public init(
        authRepository: AuthRepository,
        sessionStore: AuthSessionStore,
        deviceIdProvider: DeviceIdProvider,
        authEventBus: AuthEventBus
    ) {
        self.authRepository = authRepository
        self.sessionStore = sessionStore
        self.deviceIdProvider = deviceIdProvider
        self.authEventBus = authEventBus
    }

    public func deviceId() async -> String {
        await deviceIdProvider.ensureDeviceId()
    }

    public func loginWithEmail(email: String, password: String, rememberMe: Bool) async throws {
        let deviceId = await deviceId()
        let response = try await authRepository.loginWithEmail(
            LoginWithEmailRequest(email: email, password: password, deviceId: deviceId)
        )
        try await complete(response, rememberMe: rememberMe, deviceId: deviceId)
    }

    /** step-1 响应（邮箱登录或 Google）→ 完整的 community 会话。 */
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
        let selected = try await authRepository.selectProfile(
            SelectProfileRequest(profileId: community.profileId, kind: .community, deviceId: deviceId)
        )
        sessionStore.setTokens(TokensResponse(accessToken: selected.accessToken, refreshToken: selected.refreshToken))
        sessionStore.setCurrentAccountId(selected.accountId)
        sessionStore.setCurrentProfileId(selected.profileId)
        sessionStore.setCurrentProfileKind(.community)
        authEventBus.emit(.loginSuccess(accountId: selected.accountId))
    }
}

/** 每个账号注册时都会建 community 身份；登录响应里没有它说明后端数据不完整。 */
public struct MissingCommunityProfileError: Error, Sendable {}
