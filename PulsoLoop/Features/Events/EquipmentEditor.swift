import PulsoLinkUI
import SwiftUI

/**
 * 活动的装备要求（Android `EquipmentEditor`，WEB `EquipmentTransfer`）：已选的可删除标签、点一下就加的预设、
 * 再加一行自定义。名字不重复，最多 [eventEquipmentMax] 条。
 */
struct EquipmentEditor: View {
    let value: [EquipmentDraft]
    let presets: [EquipmentDraft]
    let onChange: ([EquipmentDraft]) -> Void
    var enabled = true

    @State private var custom = ""
    @State private var customError: String?

    private var full: Bool { value.count >= eventEquipmentMax }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if value.isEmpty {
                Text("create_equipment_selected_empty").font(.footnote).foregroundStyle(.secondary)
            } else {
                PulsoFlowLayout(spacing: 8) {
                    ForEach(value, id: \.self) { item in
                        Button { onChange(value.filter { $0 != item }) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: EventEquipment(name: item.name, icon: item.icon).systemImage)
                                Text(verbatim: item.name)
                                Image(systemName: "xmark").font(.caption2.bold())
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                        .accessibilityLabel(Text(verbatim: item.name))
                        .accessibilityHint(Text("create_photo_remove"))
                    }
                }
            }
            let remaining = presets.filter { !has($0.name) }
            if !remaining.isEmpty {
                Text("create_equipment_presets").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                PulsoFlowLayout(spacing: 8) {
                    ForEach(remaining, id: \.self) { preset in
                        Button { _ = add(preset) } label: {
                            Label { Text(verbatim: preset.name) } icon: { Image(systemName: EventEquipment(name: preset.name, icon: preset.icon).systemImage) }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.fill.tertiary, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled || full)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("create_equipment_custom_placeholder", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: custom) { _, next in
                        if next.count > eventEquipmentNameMax { custom = String(next.prefix(eventEquipmentNameMax)) }
                        customError = nil
                    }
                    .disabled(!enabled || full)
                Button {
                    if add(EquipmentDraft(icon: defaultCatalogIcon, name: custom)) { custom = "" }
                } label: {
                    Label("create_equipment_add", systemImage: "plus")
                }
                .buttonStyle(.pulso(.soft))
                .disabled(!enabled || full || custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let customError {
                Text(verbatim: customError).font(.footnote).foregroundStyle(.red)
            }
            Text(verbatim: localizedFormat("create_equipment_limit", eventEquipmentMax))
                .font(.footnote)
                .foregroundStyle(full ? Color.red : Color.secondary)
        }
    }

    private func has(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return value.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func add(_ draft: EquipmentDraft) -> Bool {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return false }
        if has(name) {
            customError = localizedFormat("create_equipment_duplicate", eventEquipmentMax)
            return false
        }
        if full {
            customError = localizedFormat("create_equipment_limit", eventEquipmentMax)
            return false
        }
        customError = nil
        onChange(value + [EquipmentDraft(icon: draft.icon, name: name)])
        return true
    }
}
