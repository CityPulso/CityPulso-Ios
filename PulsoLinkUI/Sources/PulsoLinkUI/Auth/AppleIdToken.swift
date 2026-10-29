import AuthenticationServices

/** 「通过 Apple 登录」成功却没给 identity token。 */
public struct AppleIdentityTokenMissingError: Error {}

/** 系统「通过 Apple 登录」按钮的结果里，发给 POST /auth/login/with-apple 的部分。 */
public struct AppleIdToken: Sendable {
    public let identityToken: String
    /** Apple 只在第一次授权时给名字；之后为 nil。 */
    public let displayName: String?

    /** 系统按钮请求的授权范围：名字给新账号起名，邮箱用来认出已有账号。 */
    public static let scopes: [ASAuthorization.Scope] = [.fullName, .email]

    /** - Returns: nil 表示用户取消，什么都不用提示。 */
    public static func from(_ result: Result<ASAuthorization, any Error>) throws -> AppleIdToken? {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8)
            else { throw AppleIdentityTokenMissingError() }
            let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            return AppleIdToken(identityToken: token, displayName: name?.isEmpty == false ? name : nil)
        case let .failure(error as ASAuthorizationError) where error.code == .canceled:
            return nil
        case let .failure(error):
            throw error
        }
    }
}
