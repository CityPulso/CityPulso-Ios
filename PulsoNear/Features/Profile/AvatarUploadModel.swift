import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 头像：选图 → 上传（待确认）→ 确认（对应 Android `AvatarUploadController`）。
 * 换图或放弃时，服务端那张待确认的图会被丢掉；确认后广播账号已更新，各页的资料随之刷新。
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
                image.data, fileName: image.fileName, mimeType: image.mimeType, category: .avatar
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
            try await assets.confirmPending(imageId: id, category: .avatar)
            pendingImageId = nil
            isPresented = false
            authService.notifyAccountUpdated()
            PulsoMessageCenter.shared.success("avatar_upload_success")
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
