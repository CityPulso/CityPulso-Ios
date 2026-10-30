import PhotosUI
import PulsoLinkUI
import SwiftUI

/** 上传头像的弹层（对应 Android `AvatarUploadSheet` / `PulsoAvatarUploadDialog`）：系统相册选图，预览，保存。 */
struct AvatarUploadSheet: View {
    @Bindable var model: AvatarUploadModel
    var title: LocalizedStringKey = "avatar_upload_title"
    @State private var selection: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("avatar_upload_pick_hint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ZStack {
                    if let preview = model.preview {
                        preview.resizable().scaledToFill()
                    } else {
                        ContentUnavailableView {
                            Label("avatar_upload_choose", systemImage: "photo.badge.plus")
                        } description: {
                            Text("avatar_upload_empty_hint")
                        }
                    }
                    if model.isBusy {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(width: 240, height: 240)
                .background(.fill.tertiary)
                .clipShape(.circle)

                let uploading = model.isUploading
                PhotosPicker(selection: $selection, matching: .images) {
                    Label(uploading ? "avatar_upload_uploading" : "avatar_upload_choose", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isBusy)
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("avatar_upload_close", systemImage: "xmark", role: .cancel) {
                        model.isPresented = false
                    }
                    .disabled(model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isConfirming ? "avatar_upload_confirming" : "avatar_upload_confirm", role: .confirm) {
                        Task { await model.confirm() }
                    }
                    .disabled(model.pendingImageId == nil || model.isBusy)
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                selection = nil
                Task { await model.pick(item) }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /** 挂上头像弹层。 */
    func avatarUploadSheet(_ model: AvatarUploadModel, title: LocalizedStringKey = "avatar_upload_title") -> some View {
        sheet(isPresented: Bindable(model).isPresented, onDismiss: { model.dismissed() }) {
            AvatarUploadSheet(model: model, title: title)
        }
    }
}
