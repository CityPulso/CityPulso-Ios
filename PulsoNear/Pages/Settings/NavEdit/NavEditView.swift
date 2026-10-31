import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 导航栏编辑（对应 Android `NavEditScreen`）：上面是真实底栏的实时预览，点哪个图标就编辑哪个槽位。 */
struct NavEditView: View {
    @State private var model = NavEditModel()
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("settings_nav_edit_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, PulsoSpace.s2)

                // 和真机底栏一样的实时预览，点格位打开编辑（格位 1 高亮：打开 app 时的首页）。
                VStack(spacing: PulsoSpace.s4) {
                    Text("settings_nav_live_preview")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    PulsoFloatingShellNavigation(
                        slots: model.draft.capsuleSlots,
                        action: model.draft.slot6,
                        trayDestinations: [],
                        selection: model.draft.slot1.destination,
                        appsExpanded: .constant(false),
                        onOpen: { model.beginPick(destination: $0) }
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: PulsoSpace.s2) {
                    Text("settings_nav_slots_title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    Text("settings_nav_home_hint")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Grid(horizontalSpacing: PulsoSpace.s2, verticalSpacing: PulsoSpace.s2) {
                        GridRow {
                            slotChip(1, corner: "house.fill")
                            slotChip(2)
                            slotChip(3)
                        }
                        GridRow {
                            slotChip(4)
                            chip(
                                title: Text(verbatim: localizedFormat("settings_nav_slot", 5)),
                                subtitle: Text("settings_nav_apps_locked"),
                                systemImage: "square.grid.3x3",
                                corner: "lock.fill",
                                action: nil
                            )
                            slotChip(6)
                        }
                    }
                }
            }
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.bottom, PulsoSpace.s4)
        }
        .navigationTitle("settings_nav_edit")
        // 底部两个按钮直接铺在页面底（Android：没有底托色块）。
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: PulsoSpace.s2) {
                Button("settings_nav_reset_defaults") { model.resetToDefaults() }
                    .buttonStyle(.pulso(.outline, tone: .gray, fullWidth: true))
                Button {
                    saving = true
                    Task {
                        await model.save()
                        saving = false
                        dismiss()
                    }
                } label: {
                    PulsoButtonLabel("settings_nav_confirm", loading: saving)
                }
                .buttonStyle(.pulso(fullWidth: true))
                .disabled(saving)
            }
            .padding([.horizontal, .bottom], PulsoSpace.s4)
        }
        .sheet(isPresented: Binding(get: { model.editingSlot != nil }, set: { if !$0 { model.cancelPick() } })) {
            NavSlotEditorSheet(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    private func slotChip(_ slot: Int, corner: String? = nil) -> some View {
        let navSlot = model.draft.slot(slot)
        return chip(
            title: Text(verbatim: localizedFormat("settings_nav_slot", slot)),
            subtitle: Text(navSlot.destination.labelKey),
            systemImage: navSlot.iconPack.systemImage,
            corner: corner
        ) { model.beginPick(slot) }
    }

    /** 一个格位卡片（Android `NavEditSlotChip`）：图标、「格位 N」、目标名；右上角首页 / 固定标记。 */
    private func chip(title: Text, subtitle: Text, systemImage: String, corner: String?, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            PulsoCard {
                VStack(spacing: PulsoSpace.s1) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(palette.text)
                        .frame(width: 28, height: 28)
                    title.font(.caption.weight(.semibold)).foregroundStyle(palette.text)
                    subtitle.font(.caption2).foregroundStyle(palette.secondaryText).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(PulsoSpace.s2)
                .overlay(alignment: .topTrailing) {
                    if let corner {
                        Image(systemName: corner)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText)
                            .padding(PulsoSpace.s2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

/** 编辑一个槽位：选页面、选图标组，点完成写回草稿。 */
private struct NavSlotEditorSheet: View {
    @Bindable var model: NavEditModel

    var body: some View {
        NavigationStack {
            Form {
                if let draft = model.editingDraft {
                    Section("settings_nav_pick_destination") {
                        Picker(selection: Binding(get: { draft.destination }, set: { model.setEditingDestination($0) })) {
                            ForEach(model.destinations, id: \.self) { destination in
                                Label(destination.labelKey, systemImage: destination.defaultIconPack.systemImage)
                                    .tag(destination)
                            }
                        } label: {
                            Text("settings_nav_pick_destination")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section("settings_nav_pick_icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                            ForEach(ShellNavIconPack.allCases, id: \.self) { pack in
                                Button {
                                    model.setEditingIconPack(pack)
                                } label: {
                                    Image(systemName: pack.systemImage)
                                        .symbolVariant(pack == draft.iconPack ? .fill : .none)
                                        .font(.title3)
                                        .frame(width: 48, height: 48)
                                        .foregroundStyle(pack == draft.iconPack ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                        .background {
                                            if pack == draft.iconPack {
                                                Circle().fill(.fill.tertiary)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(pack.labelKey))
                                .accessibilityAddTraits(pack == draft.iconPack ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(model.editingSlot == 6 ? Text("settings_nav_slot6") : Text(verbatim: localizedFormat("settings_nav_slot", model.editingSlot ?? 0)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.cancelPick() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings_nav_apply_slot") { model.applyEditingSlot() }
                }
            }
        }
    }
}
