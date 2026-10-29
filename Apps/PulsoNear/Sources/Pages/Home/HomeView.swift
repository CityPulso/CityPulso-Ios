import PulsoLinkUI
import SwiftUI

/** 登录后的落地页。主壳（底栏、地图、活动）还没移植，先只放退出登录。 */
struct HomeView: View {
    let session: PulsoSessionModel
    @Environment(\.pulsoTheme) private var theme

    var body: some View {
        VStack(spacing: theme.dimensions.space5) {
            Spacer()
            PulsoButton("settings_logout", systemImage: "rectangle.portrait.and.arrow.right", variant: .soft) {
                Task { await session.signOut() }
            }
            .padding(.horizontal, theme.dimensions.space5)
        }
        .padding(.bottom, theme.dimensions.space6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
    }
}
