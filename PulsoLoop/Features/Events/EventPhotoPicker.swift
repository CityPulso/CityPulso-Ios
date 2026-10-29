import PhotosUI
import PulsoLinkUI
import SwiftUI

/**
 * 发起表单的封面 + 照片条（Android `EventPhotoPicker`）：第一张是带徽标的大封面，其余是缩略图，还有空位时
 * 显示「添加」。每张都显示上传状态，失败的可以重试；点缩略图设为封面。
 */
struct EventPhotoPicker: View {
    let photos: [EventPhotoDraft]
    /** 本地选中、还没确认的照片数据（上传中 / 失败时显示它）。 */
    let localData: [String: Data]
    let imageURL: (String?) -> URL?
    let onAdd: ([(data: Data, mimeType: String)]) -> Void
    let onRemove: (EventPhotoDraft) -> Void
    let onSetCover: (EventPhotoDraft) -> Void
    let onRetry: (EventPhotoDraft) -> Void
    var enabled = true
    var max = eventPhotosMax

    @State private var selection: [PhotosPickerItem] = []

    private var canAdd: Bool { enabled && photos.count < max }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let cover = photos.first {
                photo(cover)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        Label("create_photo_cover_badge", systemImage: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: .capsule)
                            .padding(12)
                    }
                    .overlay(alignment: .topTrailing) { controls(cover).padding(12) }
                    .overlay(alignment: .bottomLeading) { status(cover, compact: false).padding(12) }
            } else {
                picker {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.largeTitle)
                        Text("create_photo_add_cover").font(.subheadline.weight(.semibold))
                        Text(verbatim: localizedFormat("create_photo_hint", max)).font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 16))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos.dropFirst()) { item in
                        Button { onSetCover(item) } label: {
                            photo(item).frame(width: 88, height: 88).clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled || item.status != .ready)
                        .overlay(alignment: .topTrailing) { controls(item, small: true).padding(4) }
                        .overlay(alignment: .bottomLeading) { status(item, compact: true).padding(4) }
                    }
                    if !photos.isEmpty, canAdd {
                        picker {
                            VStack(spacing: 4) {
                                Image(systemName: "plus").font(.title3)
                                Text("create_photo_add").font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 88, height: 88)
                            .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.4)))
                        }
                    }
                }
            }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            selection = []
            Task { await load(items) }
        }
    }

    private func picker(@ViewBuilder label: () -> some View) -> some View {
        PhotosPicker(selection: $selection, maxSelectionCount: Swift.max(1, max - photos.count), matching: .images) {
            label()
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
    }

    @ViewBuilder
    private func photo(_ item: EventPhotoDraft) -> some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if let data = localData[item.localId], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                PulsoRemoteImage(url: imageURL(item.imageId))
            }
        }
        .clipped()
    }

    private func controls(_ item: EventPhotoDraft, small: Bool = false) -> some View {
        HStack(spacing: 6) {
            if item.status == .failed {
                overlayButton("arrow.clockwise", small: small) { onRetry(item) }
                    .accessibilityLabel(Text("create_photo_retry"))
            }
            overlayButton("xmark", small: small) { onRemove(item) }
                .accessibilityLabel(Text("create_photo_remove"))
        }
    }

    private func overlayButton(_ systemImage: String, small: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(small ? .caption2.bold() : .footnote.bold())
                .frame(width: small ? 22 : 32, height: small ? 22 : 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func status(_ item: EventPhotoDraft, compact: Bool) -> some View {
        switch item.status {
        case .ready:
            EmptyView()
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).tint(.white)
                if !compact { Text("create_photo_uploading").font(.caption2) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: .capsule)
        case .failed:
            Text("create_photo_failed")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red, in: .capsule)
        }
    }

    /** 按选择顺序读出图片数据；HEIC 等格式统一转成 JPEG 再传。 */
    private func load(_ items: [PhotosPickerItem]) async {
        var picked: [(data: Data, mimeType: String)] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .png) }) {
                picked.append((data, "image/png"))
            } else if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
                picked.append((jpeg, "image/jpeg"))
            }
        }
        onAdd(picked)
    }
}
