import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 头像：选图 → 上传（待确认）→ 确认（对应 Android `AvatarUploadController`）。换图或放弃时，服务端那张待确认的图会被丢掉。
 * 自己的头像（[AssetCategory.avatar]，没有 [onConfirmed]）：确认时服务端就设好了，再广播账号已更新，各页的资料随之刷新。
 * 别的图（群头像）：确认后把图片 id 交给 [onConfirmed]，由它放到该放的地方并报告结果。
 */
@MainActor
@Observable
final class AvatarUploadModel {
    var isPresented = false
    private(set) var preview: Image?
    private(set) var pendingImageId: String?
    private(set) var isUploading = false
    private(set) var isConfirming = false

    @ObservationIgnored @Injected(\.assetRepository) private var assets
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored private let category: AssetCategory
    @ObservationIgnored private let onConfirmed: (@MainActor (String) async throws -> Void)?

    init(category: AssetCategory = .avatar, onConfirmed: (@MainActor (String) async throws -> Void)? = nil) {
        self.category = category
        self.onConfirmed = onConfirmed
    }

    var isBusy: Bool { isUploading || isConfirming }

    func open() {
        reset()
        isPresented = true
    }

    func pick(_ item: PhotosPickerItem) async {
        let previous = pendingImageId
        pendingImageId = nil
        isUploading = true
        defer { isUploading = false }
        if let previous { await assets.discardPending(imageId: previous) }
        do {
            guard let image = try await PickedImage.load(item, defaultName: "avatar.jpg") else { return }
            preview = UIImage(data: image.data).map(Image.init(uiImage:))
            pendingImageId = try await assets.putImage(
                image.data, fileName: image.fileName, mimeType: image.mimeType, category: category
            ).imageId
        } catch {
            preview = nil
            PulsoMessageCenter.shared.error(error, fallback: "profile_upload_failed")
        }
    }

    func confirm() async {
        guard let id = pendingImageId, !isBusy else { return }
        isConfirming = true
        defer { isConfirming = false }
        do {
            try await assets.confirmPending(imageId: id, category: category)
            pendingImageId = nil
            isPresented = false
            if let onConfirmed {
                try await onConfirmed(id)
            } else {
                authService.notifyAccountUpdated()
                PulsoMessageCenter.shared.success("avatar_upload_success")
            }
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "profile_upload_failed")
        }
    }

    /** 关掉弹层：丢掉没确认的图（尽力而为，服务端过期也会清）。 */
    func dismissed() {
        guard let pending = pendingImageId else { return }
        reset()
        Task { await assets.discardPending(imageId: pending) }
    }

    private func reset() {
        preview = nil
        pendingImageId = nil
    }
}
