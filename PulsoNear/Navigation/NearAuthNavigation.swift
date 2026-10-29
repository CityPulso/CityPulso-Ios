import SwiftUI

/** 未登录时的页面（对应 Android 认证栈的 NavKey）：欢迎页是栈底，登录 / 注册推进来。 */
enum AuthRoute: Hashable {
    case login
    case signup
}

/** 认证栈导航（对应 Android `WelcomeNavigator` / `LoginNavigator` / `SignupNavigator`）：登录和注册互相切换时替换，不叠加。 */
@MainActor
@Observable
final class AuthNavigator {
    var path: [AuthRoute] = []

    func openLogin() {
        path = [.login]
    }

    func openSignup() {
        path = [.signup]
    }
}

/** 未登录界面：系统导航栈，欢迎页在底。 */
struct NearAuthStack: View {
    @State private var navigator = AuthNavigator()

    var body: some View {
        NavigationStack(path: $navigator.path) {
            WelcomeView()
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .login: LoginView()
                    case .signup: SignupView()
                    }
                }
        }
        .environment(navigator)
    }
}
