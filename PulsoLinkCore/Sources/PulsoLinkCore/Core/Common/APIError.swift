import Foundation

/** 后端统一错误体（与 PulsoLink WEB `ApiErrorBody` 一致；wire 为 snake_case）。 */
public struct APIErrorBody: Codable, Sendable, Equatable {
    public var status: Int?
    public var errCode: String?
    public var message: String?
    public var traceId: String?
}

/** HTTP 层错误：携带 status + 后端 errCode/message，供 UI 与刷新逻辑判定。 */
public struct APIError: Error, Sendable, Equatable {
    public let status: Int
    public let errCode: String?
    public let message: String?
    public let traceId: String?

    public init(status: Int, errCode: String? = nil, message: String? = nil, traceId: String? = nil) {
        self.status = status
        self.errCode = errCode
        self.message = message
        self.traceId = traceId
    }

    /**
     * 从失败响应构造（对应 Android `HttpException.toApiException`）：
     * 网关原文（Bad Gateway、HTML 502 页）不进 UI；502–504 / 408 没有后端 message 时留空，由 UI 用通用文案。
     */
    public init(status: Int, body: Data?) {
        let decoded = body.flatMap { try? WireCoding.decoder.decode(APIErrorBody.self, from: $0) }
        self.init(
            status: status,
            errCode: decoded?.errCode,
            message: decoded?.message.takeUnlessInfrastructureNoise(),
            traceId: decoded?.traceId
        )
    }

    /** 是否因会话范围/角色类错误应立即强制登出（对应 WEB `shouldImmediateForceLogoutOnApiError`）。 */
    public var shouldImmediateForceLogout: Bool {
        errCode.map(ErrorCodes.immediateForceLogout.contains) ?? false
    }
}

/** 与后端约定的关键错误码（对应 WEB tokenRefresh.ts / sessionErrors.ts 的集合）。 */
public enum ErrorCodes {
    public static let refreshTokenNotFound = "REFRESH_TOKEN_NOT_FOUND"
    public static let invalidRefreshToken = "INVALID_REFRESH_TOKEN"
    public static let invalidToken = "INVALID_TOKEN"
    public static let authorityProfileScopeRequired = "AUTHORITY_PROFILE_SCOPE_REQUIRED"
    public static let authorityProfileInsufficientRole = "AUTHORITY_PROFILE_INSUFFICIENT_ROLE"

    /** refresh 换票 hard-fail：清会话、不再重试（WEB HARD_REFRESH_FAILURE_ERR_CODES）。 */
    public static let hardRefreshFailure: Set<String> = [refreshTokenNotFound, invalidRefreshToken]

    /** 档案范围/角色错误或非法 refresh：应立即强制登出（WEB IMMEDIATE_FORCE_LOGOUT_ERR_CODES）。 */
    public static let immediateForceLogout: Set<String> = [
        authorityProfileScopeRequired,
        authorityProfileInsufficientRole,
        invalidRefreshToken,
    ]
}

extension String {
    /** Traefik / 网关原文（Bad Gateway、HTML 502 页）不能进 UI。 */
    var isInfrastructureHTTPNoise: Bool {
        let lower = lowercased()
        if contains("<"), lower.contains("html") || lower.contains("doctype") { return true }
        if lower.contains("bad gateway") || lower.contains("service unavailable") || lower.contains("gateway timeout") {
            return true
        }
        return hasPrefix("HTTP 5") || hasPrefix("HTTP 408") || hasPrefix("HTTP 504")
    }
}

extension Optional where Wrapped == String {
    func takeUnlessInfrastructureNoise() -> String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, !trimmed.isInfrastructureHTTPNoise
        else { return nil }
        return trimmed
    }
}
