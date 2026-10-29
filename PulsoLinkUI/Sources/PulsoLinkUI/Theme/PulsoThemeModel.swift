import Factory
import PulsoLinkCore
import SwiftUI

/** 当前主题偏好（随服务端 / 本地偏好变化），给根视图套 `.pulsoTheme(_:)`。 */
@MainActor
@Observable
public final class PulsoThemeModel {
    public private(set) var settings: PulsoThemeSettings

    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?

    public init() {
        let preferences = Container.shared.preferenceService()
        settings = preferences.preference.value.theme
        let values = preferences.themeSettingsValues()
        task = Task { [weak self] in
            for await value in values { self?.settings = value }
        }
    }

    deinit {
        task?.cancel()
    }
}
