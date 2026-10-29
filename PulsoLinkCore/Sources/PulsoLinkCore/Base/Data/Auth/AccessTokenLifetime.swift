import Foundation
#if os(iOS) || os(macOS)
import JWTDecode
#endif

/** access token 的签发 / 过期时间（只读 claim，不验签；验签在服务端）。 */
struct AccessTokenLifetime: Sendable {
    let issuedAt: Date?
    let expiresAt: Date

    init?(jwt: String) {
        #if os(iOS) || os(macOS)
        guard let decoded = try? decode(jwt: jwt), let expiresAt = decoded.expiresAt else { return nil }
        self.issuedAt = decoded.issuedAt
        self.expiresAt = expiresAt
        #else
        return nil
        #endif
    }
}
