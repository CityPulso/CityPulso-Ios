import Foundation

public let emptyAccountId = "00000000-0000-0000-0000-000000000000"
public let emptyProfileId = "00000000-0000-0000-0000-000000000000"

public func hasSelectedProfile(_ profileId: String) -> Bool {
    profileId != emptyProfileId && !profileId.trimmingCharacters(in: .whitespaces).isEmpty
}

/**
 * 认证会话快照（与 WEB `stores/auth.ts` 的 AuthState 字段一致）：
 * - 内存（[AuthSessionStore]）是运行时真相。
 * - 仅「已选 profile 且 rememberMe」的完整会话落盘；step-1（仅 account token）只留内存。
 */
public struct AuthSession: Sendable, Equatable {
    public var isAuthValid: Bool
    public var accessToken: String?
    public var refreshToken: String?
    public var currentAccountId: String
    /** 当前选中的 profile（community/authority 统一 profileId），与 access token 内 profile_id 一致 */
    public var currentProfileId: String
    /** 当前选中 profile 的档位，决定拉哪个 with-*-profile 读模型 */
    public var currentProfileKind: ProfileKind
    /** true → 持久化（跨重启）；false → 仅本进程内存 */
    public var rememberMe: Bool

    public var hasSelectedProfile: Bool { PulsoLinkCore.hasSelectedProfile(currentProfileId) }

    /** 可落盘的「完整会话」：有效 + 双 token + 已选 profile */
    public var isCompleteSession: Bool {
        isAuthValid && !(accessToken ?? "").isEmpty && !(refreshToken ?? "").isEmpty && hasSelectedProfile
    }

    public static let loggedOut = AuthSession(
        isAuthValid: false,
        accessToken: nil,
        refreshToken: nil,
        currentAccountId: emptyAccountId,
        currentProfileId: emptyProfileId,
        currentProfileKind: .fallback,
        rememberMe: false
    )
}

/** 记住登录时落盘的内容：JSON 编码后整份写进 Keychain（对应 Android 的 Tink 加密 DataStore）。 */
struct AuthSessionSnapshot: Codable, Sendable, Equatable {
    var isAuthValid: Bool
    var accessToken: String
    var refreshToken: String
    var accountId: String
    var profileId: String
    var profileKind: ProfileKind
}
