import Foundation

/** prepare + PUT 完成、还没 confirm 的上传。 */
public struct PendingImageUpload: Sendable, Hashable {
    public let imageId: String
}

/** 预签名 PUT 被存储拒绝（对齐 Android `ImageUploadException`），[status] 是 HTTP 状态码。 */
public struct ImageUploadError: Error, Sendable {
    public let status: Int
}

/**
 * Asset 仓储 + 上传流水线（对应 Android `AssetRepository` + `ImageUploader` + `ChatAssetUploader`）：
 * prepare → PUT 预签名 URL（不带 Bearer）→ confirm。
 */
public struct AssetRepository: Sendable {
    private let api: AssetAPI
    private let storage: APIClient

    /** [storage] 是公开客户端：预签名 URL 不能带 Bearer。 */
    public init(api: AssetAPI, storage: APIClient) {
        self.api = api
        self.storage = storage
    }

    /**
     * 一次传完并 confirm（只用于**不由业务接口再 confirm** 的场景）。
     * 背景图由 Auth PUT backgrounds 自己 confirm，必须用 [putImage]，图片要留在 tmp。
     */
    public func uploadImage(_ data: Data, fileName: String, mimeType: String, category: AssetCategory) async throws -> String {
        let pending = try await putImage(data, fileName: fileName, mimeType: mimeType, category: category)
        try await confirmPending(imageId: pending.imageId, category: category)
        return pending.imageId
    }

    /** prepare + PUT，不 confirm（头像待确认、背景图）。 */
    public func putImage(_ data: Data, fileName: String, mimeType: String, category: AssetCategory) async throws -> PendingImageUpload {
        let prepared = try await api.prepareImageUpload(
            PrepareUploadRequest(assetType: .image, assetCategory: category, fileName: fileName, mimeType: mimeType)
        ).dataOrThrow("PrepareImageUpload")
        try await put(data, to: prepared.uploadUrl, mimeType: mimeType)
        return PendingImageUpload(imageId: prepared.imageId)
    }

    public func confirmPending(imageId: String, category: AssetCategory) async throws {
        try await api.confirmImageUpload(ConfirmUploadRequest(imageId: imageId, assetType: .image, assetCategory: category))
    }

    /** 关掉弹层时丢掉没确认的上传；失败也不打扰用户。 */
    public func discardPending(imageId: String) async {
        try? await api.deleteImage(imageId: imageId)
    }

    /** 聊天附件（image / video / audio / file，分类 message），返回附件 id。 */
    public func uploadChatAsset(_ data: Data, fileName: String, mimeType: String, type: AssetType) async throws -> String {
        let prepared = try await api.prepareChatAssetUpload(
            segment: type.pathSegment,
            PrepareUploadRequest(assetType: type, assetCategory: .message, fileName: fileName, mimeType: mimeType)
        ).dataOrThrow("PrepareChatAssetUpload")
        let assetId: String? = switch type {
        case .image: prepared.imageId
        case .video: prepared.videoId
        case .audio: prepared.audioId
        case .file: prepared.fileId
        }
        guard let assetId else { throw MissingDataError(context: "PrepareChatAssetUpload: \(type.wireIdKey)") }
        try await put(data, to: prepared.uploadUrl, mimeType: mimeType)
        try await api.confirmChatAssetUpload(
            segment: type.pathSegment,
            ConfirmChatAssetRequest(assetType: type, assetId: assetId, assetCategory: .message)
        )
        return assetId
    }

    private func put(_ data: Data, to uploadURL: String, mimeType: String) async throws {
        guard let url = URL(string: uploadURL) else { throw URLError(.badURL) }
        let status = try await storage.upload(data, to: url, contentType: mimeType)
        guard (200..<300).contains(status) else { throw ImageUploadError(status: status) }
    }
}

/** 图片 / 附件地址（对应 Android `ImageUrls`、WEB `buildImageUrl`）。 */
public enum ImageURLs {
    /** asset 图片 id → `{apiBase}/asset/images/{id}/file`；已是绝对地址原样返回；空 id 返回 nil。 */
    public static func image(_ imageId: String?, base: URL) -> URL? {
        guard let imageId, !imageId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if imageId.hasPrefix("http://") || imageId.hasPrefix("https://") { return URL(string: imageId) }
        return base.appendingPathComponent("asset/images/\(imageId)/file")
    }

    /** 聊天附件地址（WEB `buildAttachmentUrl`）。 */
    public static func attachment(_ assetId: String?, type: AttachmentType, base: URL) -> URL? {
        guard let assetId, !assetId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if assetId.hasPrefix("http://") || assetId.hasPrefix("https://") { return URL(string: assetId) }
        let segment = switch type {
        case .image: "images"
        case .video: "videos"
        case .audio: "audios"
        case .file: "files"
        }
        return base.appendingPathComponent("asset/\(segment)/\(assetId)/file")
    }
}
