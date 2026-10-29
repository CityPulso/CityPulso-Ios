import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

@main
struct PulsoNearApp: App {
    init() {
        PulsoCoreBootstrap.start(
            config: PulsoCoreConfig(
                apiBaseURL: PulsoAppInfo.apiBaseURL,
                signupPlatform: .pulsonear,
                appName: "YouNeary",
                shellDestinations: Set(ShellDestination.allCases).subtracting([.courses, .coaching, .tournaments]),
                debugHttpLogging: PulsoAppInfo.isDebug
            ),
            vault: KeychainSessionVault(service: "com.citypulso.pulsonear.session")
        )
        PulsoUIBootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            NearRootView()
        }
    }
}
