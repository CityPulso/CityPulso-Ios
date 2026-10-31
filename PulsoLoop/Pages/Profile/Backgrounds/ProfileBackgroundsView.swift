import PhotosUI
import PulsoLinkUI
import SwiftUI

/** 背景图（对应 Android `ProfileBackgroundsScreen`）：拖动排序，第一张是封面；编辑模式下直接删除，长按设为封面。 */
struct ProfileBackgroundsView: View {
    @State private var model = ProfileBackgroundsModel()
    @State private var selection: PhotosPickerItem?

    var body: some View {
        List {
            Section {
                if model.items.isEmpty, model.loaded {
                    PulsoEmptyState(Text("profile_backgrounds_empty"))
                }
                ForEach(model.items) { item in
                    row(item)
                }
                .onMove { model.move(from: $0, to: $1) }
                .onDelete { offsets in
                    offsets.map { model.items[$0].imageId }.forEach { model.remove($0) }
                }
            } footer: {
                Text(verbatim: localizedFormat("profile_backgrounds_quota", model.items.count, ProfileBackgroundsModel.maxBackgrounds))
            }
        }
        .environment(\.editMode, .constant(.active))
        .overlay {
            if !model.loaded { ProgressView() }
        }
        .navigationTitle("profile_backgrounds_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("profile_backgrounds_upload", systemImage: "plus")
                }
                .disabled(!model.canUpload || model.busy != nil)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("profile_backgrounds_save", role: .confirm) {
                    Task { await model.save() }
                }
                .disabled(!model.canSave)
            }
        }
        .safeAreaInset(edge: .top) {
            if let busy = model.busy {
                Label { Text(busy) } icon: { ProgressView() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            Task { await model.upload(item) }
        }
        .task { await model.observe() }
        .task { await model.reload() }
        .onDisappear { model.leave() }
    }

    private func row(_ item: BackgroundItem) -> some View {
        let isCover = model.items.first?.imageId == item.imageId
        return HStack(spacing: 12) {
            PulsoRemoteImage(url: item.url)
                .frame(width: 120, height: 68)
                .clipShape(.rect(cornerRadius: 10))
            if isCover {
                Text("profile_backgrounds_cover")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: .capsule)
                    .foregroundStyle(.tint)
            }
            Spacer()
        }
        .contextMenu {
            if !isCover {
                Button("profile_backgrounds_set_cover", systemImage: "star") { model.setAsCover(item.imageId) }
            }
            Button("profile_backgrounds_remove", systemImage: "trash", role: .destructive) { model.remove(item.imageId) }
        }
    }
}
