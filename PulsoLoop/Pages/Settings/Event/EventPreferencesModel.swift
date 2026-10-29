import Factory
import PulsoLinkCore
import SwiftUI

/** 活动偏好（对应 Android `EventPreferencesViewModel`）：草稿上调滑块，点保存才写偏好并同步。 */
@MainActor
@Observable
final class EventPreferencesModel {
    private(set) var draft: ResolvedEventPreference
    private(set) var saved: ResolvedEventPreference
    private(set) var saving = false

    init() {
        let event = Container.shared.preferenceService().preference.value.event
        draft = event
        saved = event
    }

    var isDirty: Bool { draft != saved }

    /** 最小半径的上限：不超过 100 米，也要比最大半径小。 */
    var radiusMinUpper: Int {
        min(EventPreferenceLimits.radiusMinM.upperBound, draft.nearbyRadiusMaxM - 1)
    }

    func setPageSize(_ value: Int) {
        draft.nearbyPageSize = value.clamped(to: EventPreferenceLimits.pageSize)
    }

    func setRadiusMin(_ value: Int) {
        draft.nearbyRadiusMinM = value.clamped(to: EventPreferenceLimits.radiusMinM.lowerBound...radiusMinUpper)
    }

    func setRadiusMax(_ value: Int) {
        draft.nearbyRadiusMaxM = value.clamped(to: EventPreferenceLimits.radiusMaxM)
        draft.nearbyRadiusMinM = draft.nearbyRadiusMinM.clamped(to: EventPreferenceLimits.radiusMinM.lowerBound...radiusMinUpper)
    }

    /** Near 的隐藏活动类型存在同一份偏好里；只把 Loop 这边恢复默认。 */
    func resetDefaults() {
        var next = ResolvedEventPreference()
        next.hiddenNearModules = draft.hiddenNearModules
        draft = next
    }

    func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let next = draft
        await PreferenceSync.save { $0.event = next }
        saved = next
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
