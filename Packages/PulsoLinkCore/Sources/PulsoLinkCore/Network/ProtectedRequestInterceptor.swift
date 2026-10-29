import Alamofire
import Foundation

/**
 * protected 客户端的拦截器（对应 Android `AuthTokenInterceptor` + `AuthTokenAuthenticator`）：
 * - adapt：追加 `Authorization: Bearer <accessToken>`。
 * - retry：401 → 单飞刷新 → 带新 token 重放；每个请求只重放一次，刷新失败或二次 401 → 登出（仅在已选 profile 的完整会话下）。
 * - 两步登录选 profile 前的 401 属预期，不清 session。
 */
public final class ProtectedRequestInterceptor: RequestInterceptor, @unchecked Sendable {
    private let sessionStore: AuthSessionStore
    private let tokenRefreshManager: TokenRefreshManager
    private let sessionTerminator: SessionTerminator

    public init(
        sessionStore: AuthSessionStore,
        tokenRefreshManager: TokenRefreshManager,
        sessionTerminator: SessionTerminator
    ) {
        self.sessionStore = sessionStore
        self.tokenRefreshManager = tokenRefreshManager
        self.sessionTerminator = sessionTerminator
    }

    public func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, Error>) -> Void
    ) {
        var request = urlRequest
        if let token = sessionStore.state.value.accessToken, !token.isEmpty {
            request.headers.add(.authorization(bearerToken: token))
        }
        completion(.success(request))
    }

    public func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping @Sendable (RetryResult) -> Void
    ) {
        guard request.response?.statusCode == 401 else {
            completion(.doNotRetry)
            return
        }
        // 已经带新 token 重放过一次仍 401 → 放弃并登出
        guard request.retryCount == 0 else {
            logoutIfNeeded()
            completion(.doNotRetry)
            return
        }
        // 发出请求后 token 已被并发刷新换掉——直接用新 token 重放
        let sentToken = request.request?.headers.value(for: "Authorization")
        if let current = sessionStore.state.value.accessToken, sentToken != "Bearer \(current)" {
            completion(.retry)
            return
        }
        Task {
            let refreshed = (try? await tokenRefreshManager.refresh(.unauthorized)) ?? false
            if refreshed {
                completion(.retry)
            } else {
                logoutIfNeeded()
                completion(.doNotRetry)
            }
        }
    }

    private func logoutIfNeeded() {
        let session = sessionStore.state.value
        // 两步登录选 profile 前：account-scoped token 无 profile，部分接口 401 属预期，勿清 session
        guard session.isAuthValid, session.hasSelectedProfile else { return }
        let terminator = sessionTerminator
        Task { await terminator.terminate(.unauthorized) }
    }
}
