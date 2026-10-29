import Foundation

/** 刷新来源（对应 WEB AuthTokenRefreshSource）。 */
public enum TokenRefreshSource: String, Sendable {
    case proactive
    case unauthorized = "401"
}

/**
 * Token 刷新（逐条对齐 WEB `tokenRefresh.ts` / Android `TokenRefreshManager`）：
 * 1. 单飞：同一个 refresh token 只发一次 POST，并发调用方等同一个结果。
 * 2. rejected 门闩：硬失败过的 refresh token 在换票/清空前不再重试。
 * 3. 主动刷新：access token 总寿命剩 10% 时刷新；10% 缓冲 > 1h 则跳过，只靠 401 兜底。
 * 4. 硬失败（REFRESH_TOKEN_NOT_FOUND / INVALID_REFRESH_TOKEN / HTTP 404）→ [SessionTerminator]。
 */
public actor TokenRefreshManager {
    public typealias RefreshCall = @Sendable (RefreshTokensRequest) async throws -> TokensResponse

    /** 在 token 总寿命还剩 10% 时主动刷新 */
    public static let refreshRemainingRatio = 0.1
    /** 10% 缓冲超过 1 小时则不安排主动刷新（仅依赖 401 兜底） */
    public static let maxBuffer: TimeInterval = 60 * 60

    private let refreshCall: RefreshCall
    private let sessionStore: AuthSessionStore
    private let deviceIdProvider: DeviceIdProvider
    private let sessionTerminator: SessionTerminator

    private var inFlight: (refreshToken: String, task: Task<Bool, Error>)?
    private var scheduled: Task<Void, Never>?
    private var watcher: Task<Void, Never>?

    public init(
        refreshCall: @escaping RefreshCall,
        sessionStore: AuthSessionStore,
        deviceIdProvider: DeviceIdProvider,
        sessionTerminator: SessionTerminator
    ) {
        self.refreshCall = refreshCall
        self.sessionStore = sessionStore
        self.deviceIdProvider = deviceIdProvider
        self.sessionTerminator = sessionTerminator
    }

    /** App 启动时调用一次：随会话 access token 变化自动调度主动刷新。 */
    public func start() {
        guard watcher == nil else { return }
        let updates = sessionStore.state.values()
        watcher = Task { [weak self] in
            var last: String??
            for await session in updates {
                let token = session.isAuthValid ? session.accessToken : nil
                guard last != .some(token) else { continue }
                last = .some(token)
                await self?.reschedule(for: token)
            }
        }
    }

    /** 换票；成功（含「并发方已换好」）返回 true，无票/被拒返回 false，网络或后端错误抛出。 */
    public func refresh(_ source: TokenRefreshSource) async throws -> Bool {
        guard let refreshToken = sessionStore.state.value.refreshToken, !refreshToken.isEmpty else {
            debugLog("Auth refresh aborted: no refresh token (\(source.rawValue))")
            return false
        }
        if sessionStore.isRejectedRefreshToken(refreshToken) {
            debugLog("Auth refresh skipped: refresh token already rejected (\(source.rawValue))")
            return false
        }
        if let inFlight, inFlight.refreshToken == refreshToken {
            return try await inFlight.task.value
        }

        let task = Task { try await performRefresh(refreshToken, source: source) }
        inFlight = (refreshToken, task)
        defer {
            if inFlight?.refreshToken == refreshToken { inFlight = nil }
        }
        return try await task.value
    }

    public func clearScheduledRefresh() {
        scheduled?.cancel()
        scheduled = nil
    }

    /* ------------------------------ internal ------------------------------ */

    private func performRefresh(_ refreshToken: String, source: TokenRefreshSource) async throws -> Bool {
        debugLog("Refreshing auth tokens (\(source.rawValue))...")
        do {
            let tokens = try await refreshCall(
                RefreshTokensRequest(refreshToken: refreshToken, deviceId: deviceIdProvider.ensureDeviceId())
            )
            sessionStore.setTokens(tokens)
            debugLog("Auth tokens refreshed (\(source.rawValue))")
            return true
        } catch {
            debugLog("Auth token refresh failed (\(source.rawValue)): \(error)")
            if Self.isHardRefreshFailure(error) {
                clearScheduledRefresh()
                await sessionTerminator.terminate(.refreshFailed)
            }
            throw error
        }
    }

    private func reschedule(for accessToken: String?) {
        clearScheduledRefresh()
        guard let accessToken, let lifetime = AccessTokenLifetime(jwt: accessToken) else { return }
        guard let buffer = Self.refreshBuffer(expiresAt: lifetime.expiresAt, issuedAt: lifetime.issuedAt) else {
            debugLog("Proactive token refresh skipped (10% of TTL > 1h or missing iat/exp)")
            return
        }
        let delay = max(0, lifetime.expiresAt.addingTimeInterval(-buffer).timeIntervalSinceNow)
        debugLog("Access token refresh scheduled in \(Int(delay))s (10% buffer = \(Int(buffer))s)")
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            // 成功后 setTokens 触发 state 变化，由 start() 的收听重新调度
            do {
                _ = try await self?.refresh(.proactive)
            } catch {
                debugLog("Proactive refresh failed; waiting for 401 fallback: \(error)")
            }
        }
    }

    /** 主动刷新的提前量；寿命无效或 10% 超过 1 小时返回 nil。 */
    public static func refreshBuffer(expiresAt: Date, issuedAt: Date?) -> TimeInterval? {
        guard let issuedAt else { return nil }
        let lifetime = expiresAt.timeIntervalSince(issuedAt)
        guard lifetime > 0 else { return nil }
        let buffer = lifetime * refreshRemainingRatio
        return buffer > maxBuffer ? nil : buffer
    }

    static func isHardRefreshFailure(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.errCode.map(ErrorCodes.hardRefreshFailure.contains) == true || api.status == 404
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[PulsoLinkCore] \(message())")
    #endif
}
