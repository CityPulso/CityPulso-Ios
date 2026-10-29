import Foundation

/** 需 Bearer 的社交接口（对应 WEB protectedClient 的 SOCIAL 路径）。 */
public struct SocialAPI: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /* ------------------------------ 设置 ------------------------------ */

    public func getPrivacySettings() async throws -> DataResponse<PrivacySettings> {
        try await client.request(.get, "social/me/setting/privacy")
    }

    public func updatePrivacySettings(_ body: UpdatePrivacySettingsRequest) async throws -> DataResponse<PrivacySettings> {
        try await client.request(.put, "social/me/setting/privacy", body: body)
    }
}
