import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

@main
struct PulsoLoopApp: App {
    init() {
        PulsoCoreBootstrap.start(
            config: PulsoCoreConfig(
                apiBaseURL: PulsoAppInfo.apiBaseURL,
                signupPlatform: .pulsoloop,
                appName: "YouLoopy",
                shellDestinations: Set(ShellDestination.allCases),
                debugHttpLogging: PulsoAppInfo.isDebug
            ),
            vault: KeychainSessionVault(service: "com.citypulso.pulsoloop.session")
        )
        PulsoUIBootstrap.start()
        // 登录有效且选了身份时连 Centrifugo（Android `Application.onCreate`）。
        Container.shared.realtimeConnectionManager().start()
    }

    var body: some Scene {
        WindowGroup {
            LoopRootView()
        }
    }
}
