import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 主题页：改动立刻套到整个 App，停下后同步到账号。 */
struct ThemeSettingsView: View {
    @State private var theme = PulsoThemeModel()

    var body: some View {
        PulsoThemeSettingsView(settings: theme.settings) { next in
            Container.shared.preferenceService().saveTheme(next)
            PreferenceSync.pushSoon()
        }
    }
}
