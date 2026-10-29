import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/** 从相册选中的一张图：字节 + MIME + 文件名（对应 Android `ContentUriReader`）。 */
struct PickedImage: Sendable {
    let data: Data
    let mimeType: String
    let fileName: String

    /** 读 PhotosPicker 选中的项；读不到返回 nil。 */
    static func load(_ item: PhotosPickerItem, defaultName: String) async throws -> PickedImage? {
        guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
        let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
        let mime = type?.preferredMIMEType ?? "image/jpeg"
        let ext = type?.preferredFilenameExtension ?? "jpg"
        let base = (defaultName as NSString).deletingPathExtension
        return PickedImage(data: data, mimeType: mime, fileName: "\(base).\(ext)")
    }
}
