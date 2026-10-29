import Foundation

/** Asset 接口（对应 Android `AssetApi`；需 Bearer）。 */
public struct AssetAPI: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func prepareImageUpload(_ body: PrepareUploadRequest) async throws -> DataResponse<PrepareUploadResponse> {
        try await client.request(.post, "asset/images/upload-url", body: body)
    }

    public func prepareImagesUpload(_ body: PrepareImagesUploadRequest) async throws -> DataResponse<[PrepareUploadResponse]> {
        try await client.request(.post, "asset/images/upload-urls", body: body)
    }

    public func confirmImageUpload(_ body: ConfirmUploadRequest) async throws {
        try await client.send(.post, "asset/images/confirm", body: body)
    }

    public func deleteImage(imageId: String) async throws {
        try await client.send(.delete, "asset/images/\(imageId)")
    }

    public func prepareChatAssetUpload(segment: String, _ body: PrepareUploadRequest) async throws -> DataResponse<ChatAssetPrepareResponse> {
        try await client.request(.post, "asset/\(segment)/upload-url", body: body)
    }

    public func confirmChatAssetUpload(segment: String, _ body: ConfirmChatAssetRequest) async throws {
        try await client.send(.post, "asset/\(segment)/confirm", body: body)
    }
}
