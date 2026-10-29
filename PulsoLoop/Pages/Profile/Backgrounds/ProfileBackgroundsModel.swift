import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

struct BackgroundItem: Identifiable, Equatable {
    let imageId: String
    let url: URL
    /** 还没经 PUT backgrounds 提交的临时图。 */
    var isTmp = false

    var id: String { imageId }
}

/**
 * 背景图（对应 Android `ProfileBackgroundsViewModel`）：上传只传到临时区，排序 / 设封面 / 删除都在本地草稿上，
 * 点保存一次 PUT 提交全部顺序；第一张就是封面。离开时丢掉没提交的临时图。
 */
@MainActor
@Observable
final class ProfileBackgroundsModel {
    static let maxBackgrounds = 6

    private(set) var items: [BackgroundItem] = []
    private(set) var loaded = false
    private(set) var busy: LocalizedStringKey?
    private(set) var dirty = false

    @ObservationIgnored private var baselineIds: [String] = []
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.profileBootstrap) private var profileBootstrap
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.assetRepository) private var assets
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    var canUpload: Bool { items.count < Self.maxBackgrounds }
    var canSave: Bool { dirty && busy == nil && loaded }

    /** 本地有没保存的草稿时，资料刷新不覆盖它。 */
    func observe() async {
        for await info in profileStore.current.values() {
            guard let info else { continue }
            loaded = true
            guard !dirty else { continue }
            items = info.backgrounds.compactMap { background in
                ImageURLs.image(background.imageId, base: config.apiBaseURL).map { BackgroundItem(imageId: background.imageId, url: $0) }
            }
            baselineIds = items.map(\.imageId)
        }
    }

    func reload() async {
        try? await profileBootstrap.refresh()
    }

    func upload(_ item: PhotosPickerItem) async {
        guard busy == nil else { return }
        guard canUpload else {
            PulsoMessageCenter.shared.error("profile_backgrounds_max")
            return
        }
        busy = "profile_backgrounds_uploading"
        defer { busy = nil }
        do {
            guard let image = try await PickedImage.load(item, defaultName: "background.jpg") else { return }
            // 只传到临时区；保存时一次 PUT 提交顺序。
            let imageId = try await assets.putImage(image.data, fileName: image.fileName, mimeType: image.mimeType, category: .background).imageId
            guard let url = ImageURLs.image(imageId, base: config.apiBaseURL) else { return }
            commit(items + [BackgroundItem(imageId: imageId, url: url, isTmp: true)])
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "profile_upload_failed")
        }
    }

    func setAsCover(_ imageId: String) {
        guard busy == nil, let index = items.firstIndex(where: { $0.imageId == imageId }), index > 0 else { return }
        var next = items
        next.insert(next.remove(at: index), at: 0)
        commit(next)
    }

    func move(from source: IndexSet, to destination: Int) {
        guard busy == nil else { return }
        var next = items
        next.move(fromOffsets: source, toOffset: destination)
        commit(next)
    }

    func remove(_ imageId: String) {
        guard busy == nil, let removed = items.first(where: { $0.imageId == imageId }) else { return }
        commit(items.filter { $0.imageId != imageId })
        if removed.isTmp {
            Task { await assets.discardPending(imageId: imageId) }
        }
    }

    func save() async {
        guard canSave else { return }
        busy = "profile_backgrounds_saving"
        defer { busy = nil }
        let saving = items
        do {
            try await authService.confirmProfileBackgrounds(
                kind: .community,
                ConfirmProfileBackgroundsRequest(images: saving.enumerated().map { ConfirmProfileBackgroundItem(imageId: $1.imageId, sortOrder: $0) })
            )
            items = saving.map { BackgroundItem(imageId: $0.imageId, url: $0.url) }
            baselineIds = items.map(\.imageId)
            dirty = false
            PulsoMessageCenter.shared.success("profile_backgrounds_saved")
            await reload()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "profile_backgrounds_save_failed")
        }
    }

    /** 离开页面：丢掉没提交的临时图。 */
    func leave() {
        let tmp = items.filter(\.isTmp).map(\.imageId)
        dirty = false
        guard !tmp.isEmpty else { return }
        Task { for id in tmp { await assets.discardPending(imageId: id) } }
    }

    private func commit(_ next: [BackgroundItem]) {
        items = next
        dirty = next.map(\.imageId) != baselineIds
    }
}
