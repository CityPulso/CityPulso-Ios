import Foundation

/** Auth 域门面：仓储调用 + 成功后的跨模块事件（pages / stores 不直接碰 [AuthRepository]）。 */
public struct AuthService: Sendable {
    private let auth: AuthRepository
    private let authEventBus: AuthEventBus

    public init(auth: AuthRepository, authEventBus: AuthEventBus) {
        self.auth = auth
        self.authEventBus = authEventBus
    }

    public func getCurrentFullAccountInformationWithProfile(kind: ProfileKind) async throws -> CurrentFullAccountInformation {
        try await auth.getCurrentFullAccountInformationWithProfile(kind: kind)
    }

    public func updatePreference(kind: ProfileKind, preference: String) async throws {
        try await auth.updatePreference(kind: kind, preference: preference)
        authEventBus.emit(.updateAccountSuccess)
    }
}
