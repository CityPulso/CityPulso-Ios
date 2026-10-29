import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 导航栏编辑（对应 Android `NavEditScreen`）：上面是真实底栏的实时预览，点哪个图标就编辑哪个槽位。 */
struct NavEditView: View {
    @State private var model = NavEditModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                PulsoFloatingShellNavigation(
                    slots: model.draft.capsuleSlots,
                    action: model.draft.slot6,
                    trayDestinations: [],
                    selection: model.draft.slot1.destination,
                    appsExpanded: .constant(false),
                    onOpen: model.beginPick(destination:)
                )
                .padding(.horizontal, -20)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("settings_nav_live_preview")
            } footer: {
                Text("settings_nav_edit_subtitle")
            }

            Section {
                ForEach([1, 2, 3, 4], id: \.self) { slot in
                    slotRow(slot, title: Text(verbatim: localizedFormat("settings_nav_slot", slot)))
                }
                LabeledContent {
                    Text("settings_nav_apps_locked")
                } label: {
                    Label {
                        Text(verbatim: localizedFormat("settings_nav_slot", 5))
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                slotRow(6, title: Text("settings_nav_slot6"))
            } header: {
                Text("settings_nav_slots_title")
            } footer: {
                Text("settings_nav_home_hint")
            }

            Section {
                Button("settings_nav_reset_defaults", role: .destructive) {
                    model.resetToDefaults()
                }
            }
        }
        .navigationTitle("settings_nav_edit")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("settings_nav_confirm") {
                    Task {
                        await model.save()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { model.editingSlot != nil }, set: { if !$0 { model.cancelPick() } })) {
            NavSlotEditorSheet(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    private func slotRow(_ slot: Int, title: Text) -> some View {
        let navSlot = model.draft.slot(slot)
        return Button {
            model.beginPick(slot)
        } label: {
            LabeledContent {
                Text(navSlot.destination.labelKey)
            } label: {
                Label {
                    title
                } icon: {
                    Image(systemName: navSlot.iconPack.systemImage)
                }
            }
        }
        .foregroundStyle(.primary)
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
                        Picker(selection: Binding(get: { draft.destination }, set: model.setEditingDestination)) {
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
