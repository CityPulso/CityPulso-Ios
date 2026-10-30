import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

let postTitleMax = 100
let postBodyMax = 5000
let postPhotosMax = 9
let postForumsMax = 10
let postCityMax = 80

/**
 * 写帖时的一段（Android `SectionDraft`）：文字（富文本）、照片（指向帖子照片里的一张，可能还在上传）、链接。
 * 照片的接口 id 在提交时才查。
 */
enum SectionDraft: Identifiable, Hashable {
    case text(key: String, text: AttributedString)
    case photo(key: String, photoId: String?)
    case link(key: String, link: PostLink)

    var id: String {
        switch self {
        case let .text(key, _), let .photo(key, _), let .link(key, _): key
        }
    }

    static func newText(_ text: AttributedString = AttributedString()) -> SectionDraft { .text(key: UUID().uuidString, text: text) }
    static func newPhoto(_ photoId: String? = nil) -> SectionDraft { .photo(key: UUID().uuidString, photoId: photoId) }
    static func newLink(_ link: PostLink) -> SectionDraft { .link(key: UUID().uuidString, link: link) }
}

extension Array where Element == SectionDraft {
    /** 接口计数的正文：每段文字去掉首尾空白，用空行连起来。 */
    var bodyText: String {
        compactMap { draft -> String? in
            if case let .text(_, text) = draft {
                let plain = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                return plain.isEmpty ? nil : plain
            }
            return nil
        }
        .joined(separator: "\n\n")
    }

    /** 正文里放进去的照片。 */
    var placedPhotoIds: Set<String> {
        Set(compactMap { if case let .photo(_, id) = $0 { id } else { nil } })
    }

    /** 每个照片段都指向还在的照片，且除非 [allowEmpty] 至少写了点东西。 */
    func ready(photos: [EventPhotoDraft], allowEmpty: Bool) -> Bool {
        let ids = Set(photos.map(\.localId))
        let photosOk = allSatisfy { draft in
            if case let .photo(_, id) = draft { return id.map(ids.contains) ?? false }
            return true
        }
        let hasContent = contains { draft in
            if case let .text(_, text) = draft { return !String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
        return photosOk && (allowEmpty || hasContent)
    }

    /** 草稿 → 接口段落：空文字去掉，照片换成上传好的 id。 */
    func sections(photos: [EventPhotoDraft], context: Font.Context) -> [PostSection] {
        compactMap { draft -> PostSection? in
            switch draft {
            case let .text(_, text):
                guard !String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return .textSection(TextSection(contentHtml: RichTextHTML.html(text, context: context)))
            case let .photo(_, id):
                guard let imageId = photos.first(where: { $0.localId == id && $0.status == .ready })?.imageId else { return nil }
                return .imageSection(ImageSection(imageId: imageId))
            case let .link(_, link):
                return .linkSection(LinkSection(link: link))
            }
        }
    }

    func moved(from: Int, to: Int) -> [SectionDraft] {
        guard from != to, indices.contains(from), indices.contains(to) else { return self }
        var copy = self
        copy.insert(copy.remove(at: from), at: to)
        return copy
    }
}

/** 已存的正文变回草稿；照片段指向放着那张图的照片（Android `draftsOf`）。 */
@MainActor
func sectionDrafts(_ sections: [PostSection], photos: [EventPhotoDraft]) -> [SectionDraft] {
    sections.map { section in
        let key = section.id ?? UUID().uuidString
        switch section {
        case let .textSection(text): return .text(key: key, text: RichTextHTML.attributed(text.contentHtml))
        case let .imageSection(image): return .photo(key: key, photoId: photos.first { $0.imageId == image.imageId }?.localId)
        case let .linkSection(link): return .link(key: key, link: link.link)
        }
    }
}

/** 纯文字的描述 → 编辑器能读的段落（Android `paragraphsHtml`）。 */
func paragraphsHTML(_ text: String?) -> String {
    (text ?? "").components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { paragraph in
        let escaped = paragraph.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return "<p>\(escaped.replacingOccurrences(of: "\n", with: "<br>"))</p>"
    }.joined()
}

/** 段落编辑器能被锁住的部分（编辑时论坛不允许改内容 / 图片）。 */
struct SectionLocks: Hashable {
    var content = false
    var media = false
}

/**
 * 正文编辑（Android `sectionEditorItems`）：每段一行，可上下移动、删除（按住确认）；文字段是富文本，照片段选一张已上传的照片，
 * 链接段是卡片；最下面四个按钮加图片 / 文字 / 插入图片 / 链接，和「字数 · 段数」。
 */
struct SectionEditor: View {
    @Binding var sections: [SectionDraft]
    let photos: [EventPhotoDraft]
    let photoData: [String: Data]
    let imageURL: (String?) -> URL?
    let linkCards: LinkCards
    var locks = SectionLocks()
    let placeholder: LocalizedStringKey
    let onUploadPhotos: () -> Void
    let onPickLink: (_ replaceKey: String?) -> Void
    @State private var removing: SectionDraft?

    var body: some View {
        ForEach(Array(sections.enumerated()), id: \.element.id) { index, draft in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    Menu {
                        Button { sections = sections.moved(from: index, to: index - 1) } label: { Label("discussion_section_move_up", systemImage: "arrow.up") }
                            .disabled(index == 0)
                        Button { sections = sections.moved(from: index, to: index + 1) } label: { Label("discussion_section_move_down", systemImage: "arrow.down") }
                            .disabled(index == sections.count - 1)
                        Button(role: .destructive) { removing = draft } label: { Label("discussion_section_remove", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 28, height: 22)
                    }
                    .accessibilityLabel(Text("discussion_section_more"))
                }
                block(draft, index: index)
            }
        }
        addRow
            .sheet(item: $removing) { draft in
                // 按住确认（Android `holdConfirm`）。
                VStack(alignment: .leading, spacing: 16) {
                    Text("discussion_section_remove_title").font(.title3.bold())
                    Text("discussion_section_remove_body").foregroundStyle(.secondary)
                    PulsoHoldButton("discussion_section_remove") {
                        sections.removeAll { $0.id == draft.id }
                        removing = nil
                    }
                }
                .padding(24)
                .presentationDetents([.height(240)])
            }
    }

    @ViewBuilder
    private func block(_ draft: SectionDraft, index: Int) -> some View {
        switch draft {
        case let .text(key, _):
            RichTextEditor(
                text: Binding(
                    get: { if case let .text(_, value) = sections.first(where: { $0.id == key }) { value } else { AttributedString() } },
                    set: { value in if let at = sections.firstIndex(where: { $0.id == key }) { sections[at] = .text(key: key, text: value) } }
                ),
                placeholder: index == 0 ? placeholder : "discussion_section_text_placeholder",
                maxChars: postBodyMax,
                minHeight: 100,
                showCounter: false
            )
            .disabled(locks.content)
        case let .photo(key, photoId):
            photoBlock(key: key, photoId: photoId)
        case let .link(key, link):
            VStack(alignment: .leading, spacing: 6) {
                Text("discussion_section_add_link").font(.caption).foregroundStyle(.secondary)
                PostLinkCard(link: link, state: linkCards.states[link.key] ?? .loading, imageURL: imageURL)
                    .onAppear { linkCards.ensure(link) }
                Button("discussion_section_link_change") { onPickLink(key) }.font(.caption).disabled(locks.content)
            }
        }
    }

    private func photoBlock(key: String, photoId: String?) -> some View {
        let placed = sections.placedPhotoIds
        let free = photos.filter { $0.status == .ready && (!placed.contains($0.localId) || $0.localId == photoId) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("discussion_section_add_photo").font(.caption).foregroundStyle(.secondary)
            if let photoId, let photo = photos.first(where: { $0.localId == photoId }) {
                thumb(photo).frame(maxWidth: .infinity).frame(height: 180).clipShape(.rect(cornerRadius: 8))
            } else {
                Text((free.isEmpty ? "discussion_section_photo_none" : "discussion_section_photo_pick") as LocalizedStringKey).font(.footnote).foregroundStyle(.secondary)
            }
            if !free.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(free) { photo in
                            Button {
                                if let at = sections.firstIndex(where: { $0.id == key }) { sections[at] = .photo(key: key, photoId: photo.localId) }
                            } label: {
                                thumb(photo).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 6))
                                    .overlay { if photo.localId == photoId { RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 3) } }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("discussion_section_photo_choose"))
                            .disabled(locks.media)
                        }
                    }
                }
            }
            Button("discussion_section_photo_upload", systemImage: "photo.badge.plus", action: onUploadPhotos)
                .font(.caption)
                .disabled(locks.media)
        }
    }

    @ViewBuilder
    private func thumb(_ photo: EventPhotoDraft) -> some View {
        if let data = photoData[photo.localId], let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            PulsoRemoteImage(url: imageURL(photo.imageId))
        }
    }

    private var addRow: some View {
        let full = sections.count >= postSectionsMax
        let used = sections.bodyText.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tile("photo.on.rectangle.angled", "discussion_tile_upload_photos", enabled: !locks.media, action: onUploadPhotos)
                tile("text.alignleft", "discussion_tile_text", enabled: !full && !locks.content) { sections.append(.newText()) }
                tile("photo", "discussion_tile_place_photo", enabled: !full && !locks.media) { sections.append(.newPhoto()) }
                tile("link", "discussion_tile_link", enabled: !full && !locks.content) { onPickLink(nil) }
            }
            Text(verbatim: localizedFormat("discussion_section_counter", used, postBodyMax, sections.count, postSectionsMax))
                .font(.caption)
                .foregroundStyle(used > postBodyMax ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }

    private func tile(_ symbol: String, _ label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(label).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.fill.tertiary, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
