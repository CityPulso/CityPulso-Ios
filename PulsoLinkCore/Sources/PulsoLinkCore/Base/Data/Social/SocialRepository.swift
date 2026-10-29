import Foundation

/** 社交仓储——方法与 WEB `ApiSocialRepository` 逐一对齐（URL_PATHS.SOCIAL）。 */
public struct SocialRepository: Sendable {
    private let api: SocialAPI

    public init(api: SocialAPI) {
        self.api = api
    }

    public func getPrivacySettings() async throws -> PrivacySettings {
        try await api.getPrivacySettings().dataOrThrow("GetSocialPrivacySettings")
    }

    public func updatePrivacySettings(_ body: UpdatePrivacySettingsRequest) async throws -> PrivacySettings {
        try await api.updatePrivacySettings(body).dataOrThrow("UpdateSocialPrivacySettings")
    }
}
