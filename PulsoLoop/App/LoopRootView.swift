import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 开屏门闩放行前显示加载；之后按会话在登录与主界面之间切换。主题跟随偏好。 */
struct LoopRootView: View {
    @State private var session = PulsoSessionModel()
    @State private var theme = PulsoThemeModel()

    var body: some View {
        ZStack {
            if !session.isReady {
                ProgressView()
            } else if session.isSignedIn {
                LoopRootChrome()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isSignedIn)
        .environment(session)
        .pulsoTheme(theme.settings)
    }
}
