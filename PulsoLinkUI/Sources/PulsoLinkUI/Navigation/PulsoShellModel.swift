import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 主壳状态（对应 Android `LoopRootChromeViewModel`）：按当前身份和本 App 规范化后的底栏槽位、「应用」里的其余页面。
 * 打开 App 落在槽 1；偏好变化后当前 Tab 已不在底栏上时也回到槽 1。
 */
@MainActor
@Observable
public final class PulsoShellModel {
    public private(set) var preference: ResolvedAndroidPreference
    public var selection: PulsoShellTab

    @ObservationIgnored private let preferenceService = Container.shared.preferenceService()
    @ObservationIgnored private let sessionStore = Container.shared.authSessionStore()
    @ObservationIgnored private let supported = Container.shared.pulsoCoreConfig().shellDestinations
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?

    public init() {
        let current = preferenceService.androidPreference
        preference = current
        selection = .destination(current.slot1.destination)
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
        if case let .destination(destination) = selection, !next.occupied.contains(destination) {
            selection = .destination(next.slot1.destination)
        }
    }
}
