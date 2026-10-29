import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 开屏门闩放行前显示加载；之后按会话在登录与主界面之间切换。主题跟随偏好。 */
struct NearRootView: View {
    @State private var session = PulsoSessionModel()
    @State private var theme = PulsoThemeModel()

    var body: some View {
        ZStack {
            if !session.isReady {
                ProgressView()
            } else if session.isSignedIn {
                NearRootChrome()
                    .transition(.opacity)
            } else {
                NearAuthStack()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isSignedIn)
        .environment(session)
        .pulsoMessageHost()
        .pulsoTheme(theme.settings)
        .onOpenURL { GoogleIdToken.handle($0) }
    }
}
