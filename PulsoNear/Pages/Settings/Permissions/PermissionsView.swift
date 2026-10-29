import SwiftUI

/** 系统授权（对应 Android `PermissionsScreen`）。 */
struct PermissionsView: View {
    @State private var model = PermissionsModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                ForEach(AppPermission.allCases) { permission in
                    Button {
                        Task { await model.tap(permission) }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: permission.systemImage)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(permission.titleKey)
                                Text(permission.bodyKey)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            status(model.statuses[permission])
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("settings_permissions_subtitle")
            }
        }
        .navigationTitle("settings_permissions_title")
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    @ViewBuilder
    private func status(_ status: PermissionStatus?) -> some View {
        switch status {
        case .granted:
            Text("settings_permission_status_granted").font(.footnote).foregroundStyle(.tint)
        case .denied, .notDetermined:
            Text("settings_permission_status_denied").font(.footnote).foregroundStyle(.red)
        case nil:
            ProgressView()
        }
    }
}
