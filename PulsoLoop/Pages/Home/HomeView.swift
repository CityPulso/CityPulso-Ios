import PulsoLinkUI
import SwiftUI

/** 登录后的落地页。主壳（Tab、地图、活动）在下一阶段替换这里，先只放退出登录。 */
struct HomeView: View {
    let session: PulsoSessionModel

    var body: some View {
        NavigationStack {
            List {
                Button("settings_logout", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        }
    }
}
