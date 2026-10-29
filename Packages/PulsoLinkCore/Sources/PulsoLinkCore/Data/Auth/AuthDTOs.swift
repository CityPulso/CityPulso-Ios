import BetterCodable
import Foundation

/*
 * 认证域 DTO——字段与 PulsoLink-Package `types/domain/auth/{login,signup,tokens}.ts` 逐一对齐；
 * wire 为 snake_case（[WireCoding] 负责映射）。
 */

/* ------------------------------- Login ------------------------------- */

/** POST /auth/login/with-email 请求 */
public struct LoginWithEmailRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let deviceId: String

    public init(email: String, password: String, deviceId: String) {
        self.email = email
        self.password = password
        self.deviceId = deviceId
    }
}

/**
 * 账号下可选择的 profile 概要（与后端 login.ProfileItem 一致）。
 * `roles` 是 community_roles / organization_roles / authority_roles 的 wire 值合集，按 [kind] 解读。
 */
public struct ProfileItem: Codable, Sendable, Hashable, Identifiable {
    public let profileId: String
    public let kind: ProfileKind
    @DefaultEmptyArray public var roles: [String]
    public let displayName: String?
    public let avatarImageId: String?
    public let city: String?
    public let country: String?

    public var id: String { profileId }
}

/** POST /auth/login/with-google 请求 */
public struct LoginWithGoogleRequest: Encodable, Sendable {
    public let idToken: String
    public let deviceId: String
    public let signupPlatform: AuthSignupPlatform
    /** 只在这次登录新建账号时使用：账号语言与设备系统。 */
    public let lang: PulsoLanguage
    public let clientOs: ClientOS

    public init(idToken: String, deviceId: String, signupPlatform: AuthSignupPlatform, lang: PulsoLanguage, clientOs: ClientOS) {
        self.idToken = idToken
        self.deviceId = deviceId
        self.signupPlatform = signupPlatform
        self.lang = lang
        self.clientOs = clientOs
    }
}

/** GET /auth/env 响应内层。 */
public struct AuthRuntimeEnv: Codable, Sendable {
    public let googleClientId: String
}

/** GET /auth/env 响应。 */
public struct AuthEnv: Codable, Sendable {
    public let env: AuthRuntimeEnv
}

/** POST /auth/login/with-email 响应 */
public struct LoginWithEmailResponse: Codable, Sendable {
    public let accountId: String
    public let accessToken: String
    public let refreshToken: String
    /** 账号下所有 profile（社区档 + 组织档 + 权限档合并），供两步登录选择 */
    @DefaultEmptyArray public var profiles: [ProfileItem]
}

/** POST /auth/me/select-profile 请求：切换当前 profile，重新签发 token */
public struct SelectProfileRequest: Encodable, Sendable {
    public let profileId: String
    public let kind: ProfileKind
    public let deviceId: String

    public init(profileId: String, kind: ProfileKind, deviceId: String) {
        self.profileId = profileId
        self.kind = kind
        self.deviceId = deviceId
    }
}

/** POST /auth/me/select-profile 响应 */
public struct SelectProfileResponse: Codable, Sendable {
    public let accountId: String
    public let profileId: String
    public let accessToken: String
    public let refreshToken: String
}

/* --------------------------- Profile / Emails --------------------------- */

/** POST /auth/me/emails 请求 */
public struct CreateEmailRequest: Encodable, Sendable {
    public let email: String
    public init(email: String) { self.email = email }
}

/** POST /auth/me/emails 响应 */
public struct CreateEmailResponse: Codable, Sendable {
    public let emailId: String
}

/** PATCH /auth/me/emails/{id} 请求 */
public struct UpdateEmailRequest: Encodable, Sendable {
    public let email: String
    public init(email: String) { self.email = email }
}

/** POST /auth/me/emails/{id}/verify 请求 */
public struct VerifyEmailRequest: Encodable, Sendable {
    public let verificationCode: String
    public init(verificationCode: String) { self.verificationCode = verificationCode }
}

/** POST /auth/me/emails/{id}/send-verification-code 请求 */
public struct SendEmailVerificationCodeRequest: Encodable, Sendable {
    public let lang: PulsoLanguage?
    public init(lang: PulsoLanguage? = nil) { self.lang = lang }
}

/** PUT /auth/me/password 请求：以主邮箱验证码为凭证设置登录密码（Google 注册的账号也能设第一个密码） */
public struct ChangePasswordRequest: Encodable, Sendable {
    public let newPassword: String
    public let verificationCode: String

    public init(newPassword: String, verificationCode: String) {
        self.newPassword = newPassword
        self.verificationCode = verificationCode
    }
}

/** POST /auth/me/password/send-verification-code 请求 */
public struct SendChangePasswordVerificationCodeRequest: Encodable, Sendable {
    public let lang: PulsoLanguage?
    public init(lang: PulsoLanguage? = nil) { self.lang = lang }
}

/** PUT /auth/me/{community|organization|authority}-profile/preference 请求（preference 为 JSON 字符串） */
public struct UpdatePreferenceRequest: Encodable, Sendable {
    public let preference: String
    public init(preference: String) { self.preference = preference }
}

/* ------------------------------- Signup ------------------------------- */

/** POST /auth/signup/send-code 请求 */
public struct SendVerificationCodeRequest: Encodable, Sendable {
    public let email: String
    public let lang: PulsoLanguage

    public init(email: String, lang: PulsoLanguage) {
        self.email = email
        self.lang = lang
    }
}

/** POST /auth/signup/with-email 请求 */
public struct SignupWithEmailRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let verificationCode: String
    public let lang: PulsoLanguage
    public let deviceId: String
    public let signupPlatform: AuthSignupPlatform
    /** 注册时的设备系统；API 据此设定初始圆角。 */
    public let clientOs: ClientOS

    public init(
        email: String,
        password: String,
        verificationCode: String,
        lang: PulsoLanguage,
        deviceId: String,
        signupPlatform: AuthSignupPlatform,
        clientOs: ClientOS
    ) {
        self.email = email
        self.password = password
        self.verificationCode = verificationCode
        self.lang = lang
        self.deviceId = deviceId
        self.signupPlatform = signupPlatform
        self.clientOs = clientOs
    }
}

/** POST /auth/signup/with-email 响应（与后端 signup.WithEmailOutput 一致） */
public struct SignupWithEmailResponse: Codable, Sendable {
    public let accountId: String
    public let profileId: String?
    public let accessToken: String
    public let refreshToken: String
}

/* ------------------------------- Tokens ------------------------------- */

/** POST /auth/refresh 请求 */
public struct RefreshTokensRequest: Encodable, Sendable {
    public let refreshToken: String
    public let deviceId: String

    public init(refreshToken: String, deviceId: String) {
        self.refreshToken = refreshToken
        self.deviceId = deviceId
    }
}

/** 换票响应（登录 / 刷新共用的 token 对） */
public struct TokensResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}
