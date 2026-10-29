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
    }

    var body: some Scene {
        WindowGroup {
            LoopRootView()
        }
    }
}
