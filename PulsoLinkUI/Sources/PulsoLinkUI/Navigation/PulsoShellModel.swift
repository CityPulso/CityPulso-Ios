import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 主壳状态（对应 Android `LoopRootChromeViewModel`）：按当前身份和本 App 规范化后的底栏槽位、「应用」里的其余页面。
 * 打开 App 落在槽 1；用户还没自己切过页面时，偏好到货后也对齐到新的槽 1。
 */
@MainActor
@Observable
public final class PulsoShellModel {
    public private(set) var preference: ResolvedAndroidPreference
    public let navigator: PulsoShellNavigator

    @ObservationIgnored private let preferenceService = Container.shared.preferenceService()
    @ObservationIgnored private let sessionStore = Container.shared.authSessionStore()
    @ObservationIgnored private let supported = Container.shared.pulsoCoreConfig().shellDestinations
    @ObservationIgnored private var autoRoot: ShellDestination?
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?

    public init() {
        let current = preferenceService.androidPreference
        preference = current
        navigator = PulsoShellNavigator(root: current.slot1.destination)
        autoRoot = current.slot1.destination
        let values = preferenceService.androidPreferenceValues()
        task = Task { [weak self] in
            for await value in values { self?.apply(value) }
        }
    }

    deinit {
        task?.cancel()
    }

    public var trayDestinations: [ShellDestination] {
        preference.appsTrayDestinations(kind: sessionStore.state.value.currentProfileKind, supported: supported)
    }

    private func apply(_ next: ResolvedAndroidPreference) {
        preference = next
        let home = next.slot1.destination
        if navigator.selection == autoRoot, home != autoRoot {
            navigator.open(home)
            autoRoot = home
        }
    }
}
