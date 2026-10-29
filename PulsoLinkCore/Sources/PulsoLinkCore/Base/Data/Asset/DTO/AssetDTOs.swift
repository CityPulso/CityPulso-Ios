import Foundation

/* Asset 领域 DTO——与 Android `AssetDtos.kt`、PulsoLink-Package `types/domain/asset/image.ts` 对齐。 */

public struct PrepareUploadRequest: Encodable, Sendable {
    public let assetType: AssetType
    public let assetCategory: AssetCategory
    public let fileName: String
    public let mimeType: String
}

public struct ConfirmUploadRequest: Encodable, Sendable {
    public let imageId: String
    public let assetType: AssetType
    public let assetCategory: AssetCategory
}

public struct PrepareUploadItem: Encodable, Sendable {
    public let fileName: String
    public let mimeType: String

    public init(fileName: String, mimeType: String) {
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

public struct PrepareImagesUploadRequest: Encodable, Sendable {
    public let assetType: AssetType
    public let assetCategory: AssetCategory
    public let items: [PrepareUploadItem]
}

/** prepare-upload 响应（单个 / 批量条目共用）。 */
public struct PrepareUploadResponse: Decodable, Sendable {
    public let imageId: String
    public let uploadUrl: String
    public let objectKey: String
}

/** 与后端 ImageDTO 一致。 */
public struct ImageDetail: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let filePath: String
    public let fileName: String
    public let fileSize: Int64
    public let mimeType: String
    public let width: Int?
    public let height: Int?
    public let altText: String?
    public let uploaderId: String
    public let createdAt: String
    public let updatedAt: String
}

/** 详情页图片项（按 sortOrder 排序）。 */
public struct ImageEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let filePath: String?
    public let altText: String?
    public let sortOrder: Int?
}

/** 聊天附件 prepare-upload 响应：id 字段名随资产类型变化。 */
public struct ChatAssetPrepareResponse: Decodable, Sendable {
    public let imageId: String?
    public let videoId: String?
    public let audioId: String?
    public let fileId: String?
    public let uploadUrl: String
    public let objectKey: String
}

/** 聊天附件 confirm：`<type>_id` 字段名随类型变化，所以手写编码。 */
public struct ConfirmChatAssetRequest: Encodable, Sendable {
    public let assetType: AssetType
    public let assetId: String
    public let assetCategory: AssetCategory

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(assetId, forKey: Key(stringValue: assetType.wireIdKey))
        try container.encode(assetType, forKey: Key(stringValue: "asset_type"))
        try container.encode(assetCategory, forKey: Key(stringValue: "asset_category"))
    }
}

extension AssetType {
    /** URL 路径段（images / videos / audios / files）。 */
    public var pathSegment: String {
        switch self {
        case .image: "images"
        case .video: "videos"
        case .audio: "audios"
        case .file: "files"
        }
    }

    /** 各类型自己的 wire id 字段名（image_id / video_id / audio_id / file_id）。 */
    var wireIdKey: String {
        "\(rawValue)_id"
    }
}
