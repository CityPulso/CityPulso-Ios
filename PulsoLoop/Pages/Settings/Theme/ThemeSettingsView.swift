import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 主题页：保存后套到整个 App，并同步到账号。 */
struct ThemeSettingsView: View {
    @State private var theme = PulsoThemeModel()

    var body: some View {
        PulsoThemeSettingsView(settings: theme.settings) { next in
            Container.shared.preferenceService().saveTheme(next)
            PreferenceSync.pushSoon()
        }
    }
}
