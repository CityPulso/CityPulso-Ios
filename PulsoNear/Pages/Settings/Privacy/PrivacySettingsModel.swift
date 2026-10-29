import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 隐私设置（对应 Android `PrivacySettingsViewModel`）：草稿上改，点保存才调一次 API。 */
@MainActor
@Observable
final class PrivacySettingsModel {
    private(set) var draft: PrivacySettings?
    private(set) var saved: PrivacySettings?
    private(set) var loadError: UiError?
    private(set) var saving = false

    @ObservationIgnored @Injected(\.socialService) private var socialService

    var isDirty: Bool { draft != nil && draft != saved }

    func load() async {
        loadError = nil
        do {
            let settings = try await socialService.getPrivacy()
            draft = settings
            saved = settings
        } catch {
            loadError = UiError(error)
        }
    }

    func edit(_ change: (inout PrivacySettings) -> Void) {
        guard var next = draft else { return }
        change(&next)
        draft = next
    }

    func save() async {
        guard let next = draft, isDirty, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let result = try await socialService.updatePrivacy(next)
            draft = result
            saved = result
            PulsoMessageCenter.shared.success("shell_privacy_saved")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_privacy_save_failed")
        }
    }
}

/** 多选受众开关：加入或移除后按固定顺序排好（与 Android `toggleAudience` 一致）。 */
func toggled<T: Equatable>(_ current: [T], _ value: T, order: [T]) -> [T] {
    let next = current.contains(value) ? current.filter { $0 != value } : current + [value]
    return order.filter(next.contains)
}
