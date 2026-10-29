import Foundation

/** Social 域门面：pages 不直接碰 [SocialRepository]。 */
public struct SocialService: Sendable {
    private let social: SocialRepository

    public init(social: SocialRepository) {
        self.social = social
    }

    public func getPrivacy() async throws -> PrivacySettings {
        try await social.getPrivacySettings()
    }

    public func updatePrivacy(_ settings: PrivacySettings) async throws -> PrivacySettings {
        try await social.updatePrivacySettings(UpdatePrivacySettingsRequest(settings))
    }
}
