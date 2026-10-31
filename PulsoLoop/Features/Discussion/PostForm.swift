import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 链接选择器打开着：[replaceKey] 是要换掉的链接段，nil 表示新加一段（Android `LinkTarget`）。 */
struct LinkTarget: Identifiable, Hashable {
    let replaceKey: String?
    var id: String { replaceKey ?? "new" }
}

/**
 * 发帖和编辑共用的草稿：正文段落、照片（选一张就开始上传到论坛分类）、链接卡片、每个论坛勾的话题。
 * 照片和段落的规则与 Android `PostCreateViewModel` / `PostEditViewModel` 一致。
 */
@MainActor
@Observable
final class PostDraft {
    var title = ""
    var kind: PostKind = .discussion
    var city = "" { didSet { if city.count > postCityMax { city = String(city.prefix(postCityMax)) } } }
    var sections: [SectionDraft] = [.newText()]
    var photos: [EventPhotoDraft] = []
    private(set) var photoData: [String: Data] = [:]
    /** 不用重新上传的照片（活动带过来的、帖子原有的）。 */
    var reusedImageIds: Set<String> = []
    var topics: [String: [ForumTopic]] = [:]
    var topicIds: [String: Set<String>] = [:]
    var linkTarget: LinkTarget?
    let linkCards = LinkCards()

    @ObservationIgnored private var photoMimeTypes: [String: String] = [:]
    @ObservationIgnored @Injected(\.assetRepository) private var assets
    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    var uploading: Bool { photos.contains { $0.status == .uploading } }
    var bodyText: String { sections.bodyText }
    var titleOk: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= postTitleMax
    }

    var topicCount: Int { topicIds.values.reduce(0) { $0 + $1.count } }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    /** 已存的照片（不用上传）。 */
    func setStoredPhotos(_ imageIds: [String]) {
        photos = imageIds.prefix(postPhotosMax).map { EventPhotoDraft(localId: UUID().uuidString, imageId: $0, status: .ready) }
        reusedImageIds = Set(imageIds)
    }

    func addPhotos(_ picked: [(data: Data, mimeType: String)]) {
        let room = postPhotosMax - photos.count
        guard room > 0 else {
            PulsoMessageCenter.shared.error(text: localizedFormat("discussion_photo_limit", postPhotosMax))
            return
        }
        for photo in picked.prefix(room) {
            let localId = UUID().uuidString
            photoData[localId] = photo.data
            photoMimeTypes[localId] = photo.mimeType
            photos.append(EventPhotoDraft(localId: localId))
            upload(localId, data: photo.data, mimeType: photo.mimeType)
        }
    }

    func retryPhoto(_ photo: EventPhotoDraft) {
        guard let data = photoData[photo.localId] else { return }
        setPhoto(photo.localId) { $0.status = .uploading }
        upload(photo.localId, data: data, mimeType: photoMimeTypes[photo.localId] ?? "image/jpeg")
    }

    /** 删掉照片时，放着它的照片段也清空（让作者重新选一张）。 */
    func removePhoto(_ photo: EventPhotoDraft) {
        photos.removeAll { $0.localId == photo.localId }
        photoData[photo.localId] = nil
        photoMimeTypes[photo.localId] = nil
        sections = sections.map { draft in
            if case let .photo(key, id) = draft, id == photo.localId { return .photo(key: key, photoId: nil) }
            return draft
        }
    }

    func setCover(_ photo: EventPhotoDraft) {
        photos.removeAll { $0.localId == photo.localId }
        photos.insert(photo, at: 0)
    }

    /** 加上选中的链接（或换掉 [LinkTarget.replaceKey] 那段）；同一个目标只链接一次。 */
    func pickLink(_ link: PostLink) {
        guard let target = linkTarget else { return }
        linkTarget = nil
        let taken = sections.contains { draft in
            if case let .link(key, existing) = draft { return existing.key == link.key && key != target.replaceKey }
            return false
        }
        if taken { return }
        if let replaceKey = target.replaceKey {
            sections = sections.map { $0.id == replaceKey ? .link(key: replaceKey, link: link) : $0 }
        } else if sections.count < postSectionsMax {
            sections.append(.newLink(link))
        }
    }

    /** 勾 / 取消一个话题；每个论坛最多 [postTopicsPerForum] 个。 */
    func toggleTopic(forumId: String, topicId: String) {
        var current = topicIds[forumId] ?? []
        if current.contains(topicId) {
            current.remove(topicId)
        } else if current.count < postTopicsPerForum {
            current.insert(topicId)
        }
        topicIds[forumId] = current
    }

    func loadTopics(_ forumIds: [String]) async {
        for id in forumIds where topics[id] == nil {
            if let list = try? await discussion.topics(id) { topics[id] = list }
        }
    }

    /** 接口要的照片：顺序就是现在的顺序。 */
    var imageInputs: [PostImageInput] {
        photos.enumerated().compactMap { index, photo in
            photo.imageId.map { PostImageInput(imageId: $0, sortOrder: index, reused: reusedImageIds.contains($0)) }
        }
    }

    private func upload(_ localId: String, data: Data, mimeType: String) {
        let ext = mimeType.split(separator: "/").last.map(String.init) ?? "jpg"
        let assets = assets
        Task {
            do {
                let imageId = try await assets.uploadImage(data, fileName: "photo.\(ext)", mimeType: mimeType, category: .forum)
                setPhoto(localId) {
                    $0.imageId = imageId
                    $0.status = .ready
                }
            } catch {
                setPhoto(localId) { $0.status = .failed }
                PulsoMessageCenter.shared.error(error, fallback: "discussion_photo_upload_failed")
            }
        }
    }

    private func setPhoto(_ localId: String, _ change: (inout EventPhotoDraft) -> Void) {
        guard let index = photos.firstIndex(where: { $0.localId == localId }) else { return }
        change(&photos[index])
    }
}

/** 正文编辑 + 照片卡，发帖和编辑页一样。 */
struct PostBodyFields: View {
    @Bindable var draft: PostDraft
    var locks = SectionLocks()
    var showPhotos: Bool
    var mediaLockedCount: Int?
    var enabled = true
    @State private var photoPickerOpen = false
    @State private var pickerSelection: [PhotosPickerItem] = []

    var body: some View {
        Section {
            SectionEditor(
                sections: $draft.sections,
                photos: draft.photos,
                photoData: draft.photoData,
                imageURL: draft.imageURL,
                linkCards: draft.linkCards,
                locks: locks,
                placeholder: "discussion_post_body_placeholder",
                onUploadPhotos: { photoPickerOpen = true },
                onPickLink: { draft.linkTarget = LinkTarget(replaceKey: $0) }
            )
        }
        .photosPicker(isPresented: $photoPickerOpen, selection: $pickerSelection, maxSelectionCount: max(1, postPhotosMax - draft.photos.count), matching: .images)
        .onChange(of: pickerSelection) { _, items in
            guard !items.isEmpty else { return }
            pickerSelection = []
            Task {
                var picked: [(data: Data, mimeType: String)] = []
                for item in items {
                    if let photo = await item.loadPhoto() { picked.append(photo) }
                }
                draft.addPhotos(picked)
            }
        }
        if showPhotos {
            Section("discussion_post_photos_title") {
                if let mediaLockedCount {
                    Text(verbatim: localizedFormat("discussion_edit_media_locked", mediaLockedCount)).font(.footnote).foregroundStyle(.secondary)
                } else {
                    EventPhotoPicker(
                        photos: draft.photos,
                        localData: draft.photoData,
                        imageURL: draft.imageURL,
                        onAdd: { draft.addPhotos($0) },
                        onRemove: { draft.removePhoto($0) },
                        onSetCover: { draft.setCover($0) },
                        onRetry: { draft.retryPhoto($0) },
                        enabled: enabled,
                        max: postPhotosMax
                    )
                }
            }
        }
    }
}

/** 发帖的论坛：谁在运营、要不要审核、勾话题（最多 [postTopicsPerForum] 个）；[onRemove] 为 nil 时不能退出（编辑页）。 */
struct SelectedForumPanel: View {
    let name: String
    let ownerScope: ProfileKind
    let avatarURL: URL?
    let reviewed: Bool
    let staff: Bool
    let topics: [ForumTopic]
    let picked: Set<String>
    let onToggleTopic: (String) -> Void
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PulsoAvatar(url: avatarURL, size: 36, fallbackText: name)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        ForumBadge(scope: ownerScope)
                    }
                    Text((staff ? "discussion_selected_staff" : reviewed ? "discussion_selected_reviewed" : "discussion_selected_direct") as LocalizedStringKey)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: localizedFormat("discussion_selected_remove", name)))
                }
            }
            if topics.isEmpty {
                Text("discussion_selected_no_topics").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(verbatim: localizedFormat("discussion_selected_topics_hint", picked.count, postTopicsPerForum)).font(.footnote).foregroundStyle(.secondary)
                PulsoFlowLayout(spacing: 6) {
                    ForEach(topics, id: \.id) { topic in
                        let on = picked.contains(topic.id)
                        Button { onToggleTopic(topic.id) } label: {
                            Label {
                                Text(verbatim: "#\(topic.name)")
                            } icon: {
                                if on { Image(systemName: "checkmark") }
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.pulso(.soft))
                        .tint(on ? .accentColor : .secondary)
                        .disabled(!on && picked.count >= postTopicsPerForum)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 12))
    }
}

/** 类型 / 论坛 / 城市三行，点开各自的面板。 */
struct PostDetailsRows: View {
    let kind: PostKind
    let forumsValue: String
    let city: String
    var eventTitle: String?
    let onKind: () -> Void
    let onForums: () -> Void
    let onCity: () -> Void

    var body: some View {
        Section {
            row("square.grid.2x2", "discussion_post_kind", String(localized: kind.labelResource), action: onKind)
            row("tag", "discussion_post_forums_row", forumsValue, action: onForums)
            row("mappin.and.ellipse", "discussion_post_city", city.isEmpty ? String(localized: "discussion_post_city_unset") : city, action: onCity)
            if let eventTitle {
                LabeledContent {
                    Text(verbatim: eventTitle).lineLimit(1)
                } label: {
                    Label("discussion_post_event_row", systemImage: "calendar")
                }
            }
        }
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent {
                HStack(spacing: 4) {
                    Text(verbatim: value).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            } label: {
                Label(title, systemImage: symbol)
            }
        }
        .tint(.primary)
    }
}

/** 选帖子类型，选完就关（Android `PostKindSheet`）。 */
struct PostKindSheet: View {
    @Binding var kind: PostKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("discussion_post_kind").font(.headline)
            PulsoFlowLayout(spacing: 8) {
                ForEach(PostKind.allCases, id: \.self) { option in
                    Button {
                        kind = option
                        dismiss()
                    } label: {
                        Text(option.labelKey).font(.subheadline)
                    }
                    .buttonStyle(.pulso(.soft))
                    .tint(option == kind ? .accentColor : .secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
    }
}

/** 改帖子的城市；输入直接写回，「完成」关掉（Android `PostCitySheet`）。 */
struct PostCitySheet: View {
    @Binding var city: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("discussion_post_city_placeholder", text: $city)
                } header: {
                    Text("discussion_post_city")
                } footer: {
                    Text("discussion_post_city_hint")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("discussion_subpage_done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension ReverseGeocodeOutput {
    /** 「Vancouver, BC」：最近结果的城市（或下一级行政区）加省 / 州代码（Android `cityLabel`）。 */
    var cityLabel: String? {
        let address = resultItems?.first?.address
        let trimmed = { (value: String?) -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return value
        }
        guard let city = trimmed(address?.locality) ?? trimmed(address?.subRegion?.name) else { return nil }
        return trimmed(address?.region?.code).map { "\(city), \($0)" } ?? city
    }
}
