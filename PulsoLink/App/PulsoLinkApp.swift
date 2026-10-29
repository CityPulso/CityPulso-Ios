import SwiftUI

/** 占位 app，与 Android `pulsolink` 一样只有一句问候。 */
@main
struct PulsoLinkApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Hello iOS!")
        }
    }
}
