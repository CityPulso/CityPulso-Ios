import SwiftUI

/** 系统授权（对应 Android `PermissionsScreen`）。 */
struct PermissionsView: View {
    @State private var model = PermissionsModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s3) {
                Text("settings_permissions_subtitle").font(.subheadline).foregroundStyle(palette.secondaryText)
                    .padding(.bottom, PulsoSpace.s1)
                // 每项权限一张卡：开关只反映系统状态，点它去申请或打开系统设置（Android 系统授权页）。
                ForEach(AppPermission.allCases) { permission in
                    let current = model.statuses[permission]
                    PulsoCard {
                        HStack(spacing: PulsoSpace.s4) {
                            Image(systemName: permission.systemImage)
                                .font(.title2)
                                .foregroundStyle(palette.accent.step(9))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: PulsoSpace.s1) {
                                Text(permission.titleKey).font(.body.weight(.medium)).foregroundStyle(palette.text)
                                Text(permission.bodyKey).font(.subheadline).foregroundStyle(palette.secondaryText)
                                status(current)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle(isOn: Binding(get: { current == .granted }, set: { _ in Task { await model.tap(permission) } })) { Text(permission.titleKey) }
                                .labelsHidden()
                                .disabled(current == nil)
                        }
                        .padding(PulsoSpace.s5)
                    }
                }
            }
            .padding(PulsoSpace.s4)
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
            Text("settings_permission_status_granted").font(.subheadline).foregroundStyle(palette.accent.step(11))
        case .denied, .notDetermined:
            Text("settings_permission_status_denied").font(.subheadline).foregroundStyle(palette.error)
        case nil:
            ProgressView().controlSize(.small)
        }
    }
}
