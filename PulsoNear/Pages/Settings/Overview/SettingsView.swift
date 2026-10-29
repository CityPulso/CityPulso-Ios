import PulsoLinkUI
import SwiftUI

/** 设置首页。各设置分页还没移植，先只有退出登录。 */
struct SettingsView: View {
    @Environment(PulsoSessionModel.self) private var session

    var body: some View {
        List {
            Section {
                Button("settings_logout", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        }
        .navigationTitle("shell_dest_settings")
    }
}
