import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 导航栏编辑（对应 Android `NavEditViewModel`）：草稿上改槽位，点保存才写偏好并同步。
 * 选的页面已在别的槽位时两槽互换，保证五槽页面不重复。
 */
@MainActor
@Observable
final class NavEditModel {
    /** 可编辑的槽位（5 号固定是「应用」）。 */
    static let editableSlots = [1, 2, 3, 4, 6]

    private(set) var draft: ResolvedAndroidPreference
    /** 正在编辑的槽位；sheet 跟着它出现。 */
    var editingSlot: Int?
    /** sheet 里的临时选择，点完成才写回 [draft]。 */
    var editingDraft: ResolvedAndroidNavSlot?

    let destinations: [ShellDestination]

    @ObservationIgnored private let supported = Container.shared.pulsoCoreConfig().shellDestinations

    init() {
        draft = Container.shared.preferenceService().androidPreference
        destinations = ShellDestination.available(for: .community, supported: supported)
    }

    func beginPick(_ slot: Int) {
        guard Self.editableSlots.contains(slot) else { return }
        editingDraft = draft.slot(slot)
        editingSlot = slot
    }

    func beginPick(destination: ShellDestination) {
        if let slot = Self.editableSlots.first(where: { draft.slot($0).destination == destination }) {
            beginPick(slot)
        }
    }

    func cancelPick() {
        editingSlot = nil
        editingDraft = nil
    }

    /** 换页时图标若还是旧页的默认组，跟着换成新页的默认组；用户改过图标就保留。 */
    func setEditingDestination(_ destination: ShellDestination) {
        guard let current = editingDraft else { return }
        let keepIcon = current.iconPack != current.destination.defaultIconPack
        editingDraft = ResolvedAndroidNavSlot(destination, iconPack: keepIcon ? current.iconPack : nil)
    }

    func setEditingIconPack(_ iconPack: ShellNavIconPack) {
        editingDraft?.iconPack = iconPack
    }

    func applyEditingSlot() {
        guard let slot = editingSlot, let navSlot = editingDraft else { return }
        let occupiedElsewhere = Self.editableSlots.first { $0 != slot && draft.slot($0).destination == navSlot.destination }
        var next = draft.withSlot(slot, navSlot)
        if let occupiedElsewhere {
            next = next.withSlot(occupiedElsewhere, draft.slot(slot))
        }
        draft = next.resolved(kind: .community, supported: supported)
        cancelPick()
    }

    /** 恢复默认布局（只改草稿，保存才生效）；桌面图标套图不动。 */
    func resetToDefaults() {
        cancelPick()
        var next = ResolvedAndroidPreference.default
        next.loopLauncherIcon = draft.loopLauncherIcon
        next.nearLauncherIcon = draft.nearLauncherIcon
        draft = next
    }

    func save() async {
        let next = draft
        await PreferenceSync.save { $0.android = next }
    }
}
