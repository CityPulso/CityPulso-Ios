import Factory
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
        // 登录有效且选了身份时连 Centrifugo（Android `Application.onCreate`）。
        Container.shared.realtimeConnectionManager().start()
    }

    var body: some Scene {
        WindowGroup {
            NearRootView()
        }
    }
}
