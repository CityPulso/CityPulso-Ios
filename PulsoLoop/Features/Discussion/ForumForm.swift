import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

let forumNameMax = 60
let forumDescriptionMax = 500

extension ForumMemberRole {
    /** 可以授予别人的角色（所有者只有一个）。 */
    static let grantable: [ForumMemberRole] = [.admin, .moderator]
}

extension ForumSettings {
    /** 摘要里数的六条主规则；「可编辑哪些部分」只在允许编辑时才有意义。 */
    var mainRules: [Bool] { [requiresPostReview, onlyFollowersCanPost, allowComments, allowReposts, allowShares, allowPostEdit] }
}

/**
 * 论坛头像（一张，必填）和背景图（1 到 [forumBackgroundsMax] 张，第一张是封面），选中就上传到论坛分类
 * （Android `ForumPicturesController`）。建论坛页和管理页各有一个。
 */
@MainActor
@Observable
final class ForumPictures {
    private(set) var avatar: EventPhotoDraft?
    private(set) var backgrounds: [EventPhotoDraft] = []
    private(set) var localData: [String: Data] = [:]

    @ObservationIgnored private var mimeTypes: [String: String] = [:]
    @ObservationIgnored @Injected(\.assetRepository) private var assets

    /** 头像和至少一张背景，都传完了。 */
    var ready: Bool {
        guard let avatar, avatar.status == .ready, avatar.imageId != nil else { return false }
        return !backgrounds.isEmpty && backgrounds.allSatisfy { $0.status == .ready && $0.imageId != nil }
    }

    var uploading: Bool { avatar?.status == .uploading || backgrounds.contains { $0.status == .uploading } }

    var backgroundInputs: [ForumImageInput] {
        backgrounds.enumerated().compactMap { index, photo in photo.imageId.map { ForumImageInput(imageId: $0, sortOrder: index) } }
    }

    /** 换成论坛已存的头像和背景（不用上传）。 */
    func reset(avatarImageId: String?, images: [ForumImage]) {
        avatar = avatarImageId.map { EventPhotoDraft(localId: UUID().uuidString, imageId: $0, status: .ready) }
        backgrounds = images.sorted { $0.sortOrder < $1.sortOrder }.map { EventPhotoDraft(localId: UUID().uuidString, imageId: $0.imageId, status: .ready) }
        localData = [:]
        mimeTypes = [:]
    }

    func pickAvatar(_ picked: (data: Data, mimeType: String)) {
        let localId = UUID().uuidString
        remember(localId, picked)
        avatar = EventPhotoDraft(localId: localId)
        upload(localId, picked)
    }

    func addBackgrounds(_ picked: [(data: Data, mimeType: String)]) {
        let room = forumBackgroundsMax - backgrounds.count
        if picked.count > room {
            PulsoMessageCenter.shared.error(text: localizedFormat("discussion_forum_backgrounds_limit", forumBackgroundsMax))
        }
        for photo in picked.prefix(max(0, room)) {
            let localId = UUID().uuidString
            remember(localId, photo)
            backgrounds.append(EventPhotoDraft(localId: localId))
            upload(localId, photo)
        }
    }

    func retryBackground(_ photo: EventPhotoDraft) {
        guard let data = localData[photo.localId] else { return }
        set(photo.localId) { $0.status = .uploading }
        upload(photo.localId, (data, mimeTypes[photo.localId] ?? "image/jpeg"))
    }

    func removeBackground(_ photo: EventPhotoDraft) {
        backgrounds.removeAll { $0.localId == photo.localId }
    }

    /** 挪到最前面：第一张是封面。 */
    func coverBackground(_ photo: EventPhotoDraft) {
        backgrounds.removeAll { $0.localId == photo.localId }
        backgrounds.insert(photo, at: 0)
    }

    private func remember(_ localId: String, _ picked: (data: Data, mimeType: String)) {
        localData[localId] = picked.data
        mimeTypes[localId] = picked.mimeType
    }

    private func upload(_ localId: String, _ picked: (data: Data, mimeType: String)) {
        let assets = assets
        let ext = picked.mimeType == "image/png" ? "png" : "jpg"
        Task {
            do {
                let imageId = try await assets.uploadImage(picked.data, fileName: "photo.\(ext)", mimeType: picked.mimeType, category: .forum)
                set(localId) {
                    $0.imageId = imageId
                    $0.status = .ready
                }
            } catch {
                set(localId) { $0.status = .failed }
                PulsoMessageCenter.shared.error(error, fallback: "discussion_photo_upload_failed")
            }
        }
    }

    private func set(_ localId: String, _ change: (inout EventPhotoDraft) -> Void) {
        if avatar?.localId == localId, var value = avatar {
            change(&value)
            avatar = value
        } else if let index = backgrounds.firstIndex(where: { $0.localId == localId }) {
            change(&backgrounds[index])
        }
    }
}

extension PhotosPickerItem {
    /** 选中的照片数据和类型。 */
    func loadPhoto() async -> (data: Data, mimeType: String)? {
        guard let data = try? await loadTransferable(type: Data.self) else { return nil }
        return (data, supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg")
    }
}

/** 论坛头像（一张）和背景图（第一张是封面），管理页用（Android `ForumPicturesEditor`）。 */
struct ForumPicturesEditor: View {
    let pictures: ForumPictures
    let imageURL: (String?) -> URL?
    var enabled = true
    @State private var avatarItem: PhotosPickerItem?

    var body: some View {
        Section {
            HStack(spacing: 12) {
                ForumAvatarThumb(pictures: pictures, remoteURL: imageURL(pictures.avatar?.imageId), size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text((pictures.avatar == nil ? "discussion_forum_avatar_pick" : "discussion_forum_avatar_change") as LocalizedStringKey)
                    }
                    .buttonStyle(.pulso(.soft))
                    .disabled(!enabled)
                    Text("discussion_forum_avatar_hint").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                avatarItem = nil
                Task { if let photo = await item.loadPhoto() { pictures.pickAvatar(photo) } }
            }
        } header: {
            Text("discussion_forum_avatar")
        }
        Section("discussion_forum_backgrounds") {
            EventPhotoPicker(
                photos: pictures.backgrounds,
                localData: pictures.localData,
                imageURL: imageURL,
                onAdd: { pictures.addBackgrounds($0) },
                onRemove: { pictures.removeBackground($0) },
                onSetCover: { pictures.coverBackground($0) },
                onRetry: { pictures.retryBackground($0) },
                enabled: enabled,
                max: forumBackgroundsMax
            )
        }
    }
}

/** 论坛头像的缩略图：本地选中的先显示本地图，上传中盖一个转圈。 */
struct ForumAvatarThumb: View {
    let pictures: ForumPictures
    /** 已上传头像的地址（调用方算好；PhotosPicker 的 label 闭包里不能传 main actor 方法）。 */
    let remoteURL: URL?
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.fill.tertiary)
            if let avatar = pictures.avatar {
                if let data = pictures.localData[avatar.localId], let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    PulsoRemoteImage(url: remoteURL)
                }
                if avatar.status == .uploading { ProgressView() }
            } else {
                Image(systemName: "camera").font(.title2).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12))
    }
}

/** 论坛的发帖规则开关，建论坛和管理页共用（Android `ForumSettingsEditor`）。 */
struct ForumSettingsEditor: View {
    @Binding var settings: ForumSettings

    var body: some View {
        Toggle(isOn: $settings.requiresPostReview) { label("discussion_setting_review", hint: "discussion_setting_review_hint") }
        Toggle(isOn: $settings.onlyFollowersCanPost) { label("discussion_setting_followers_only", hint: "discussion_setting_followers_only_hint") }
        Toggle("discussion_setting_comments", isOn: $settings.allowComments)
        Toggle("discussion_setting_reposts", isOn: $settings.allowReposts)
        Toggle("discussion_setting_shares", isOn: $settings.allowShares)
        Toggle(isOn: $settings.allowPostEdit) { label("discussion_setting_edit", hint: "discussion_setting_edit_hint") }
        Group {
            Toggle("discussion_setting_edit_title", isOn: $settings.editableTitle)
            Toggle("discussion_setting_edit_content", isOn: $settings.editableContent)
            Toggle("discussion_setting_edit_media", isOn: $settings.editableMedia)
            Toggle(isOn: $settings.editRequiresReview) { label("discussion_setting_edit_review", hint: "discussion_setting_edit_review_hint") }
        }
        .padding(.leading, 16)
        .disabled(!settings.allowPostEdit)
    }

    private func label(_ title: LocalizedStringKey, hint: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/** 论坛类型（运动 + 其他）一排横滑，点一个勾 / 取消；[keepOne] 时不能全取消（Android `ForumTypeChips` / `SportTiles`）。 */
struct ForumTypePicker: View {
    @Binding var selected: [ForumSport]
    var keepOne = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ForumSport.allCases, id: \.self) { type in
                    let on = selected.contains(type)
                    Button { toggle(type) } label: {
                        VStack(spacing: 4) {
                            if let sport = type.sport {
                                Image(sport.iconAsset).resizable().scaledToFit().frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "square.grid.2x2").font(.title2).frame(width: 32, height: 32)
                            }
                            Text(type.labelKey).font(.caption).lineLimit(1)
                        }
                        .frame(width: 72, height: 72)
                        .background(on ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 12))
                        .overlay { if on { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ type: ForumSport) {
        let next = selected.contains(type) ? selected.filter { $0 != type } : selected + [type]
        if keepOne, next.isEmpty { return }
        selected = next
    }
}
