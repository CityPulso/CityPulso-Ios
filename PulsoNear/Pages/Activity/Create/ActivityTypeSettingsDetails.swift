import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 设置步里各活动类型自己的那一块（Android `<ActivityType>SettingsDetails`）：麻将先写规则（可以点常用规则填进来），
 * 然后每种活动都是最少人数、名额和候补。
 */
struct ActivityTypeSettingsDetails: View {
    let model: CreateActivityModel
    let activityType: NearActivityKind

    private var draft: CreateDraft { model.draft }

    var body: some View {
        if activityType == .mahjong { mahjongVariant }
        Section {
            WizardCounter(label: "create_min_participants_label", value: draft.minParticipants, minimum: 1, hint: "create_min_participants_hint", systemImage: "person") { value in
                model.update { $0.minParticipants = value }
            }
            WizardCounter(label: "create_capacity_label", value: draft.capacity, minimum: 1, hint: "create_flow_capacity_hint", systemImage: "person.3") { value in
                model.update { $0.capacity = value }
            }
            WizardCounter(label: "create_waitlist_capacity_label", value: draft.waitlistCapacity, minimum: 0, hint: "create_flow_waitlist_hint", systemImage: "hourglass") { value in
                model.update { $0.waitlistCapacity = value }
            }
        } header: {
            Text("create_section_capacity")
        } footer: {
            Text("create_capacity_section_hint")
        }
    }

    /** 麻将的规则：自由文字，常用规则做成胶囊，点了填进输入框，发起人还能再改（Android `MahjongSettingsDetails`）。 */
    private var mahjongVariant: some View {
        Section {
            TextField(
                "create_mahjong_variant_label",
                text: Binding(get: { draft.mahjongVariant }, set: { value in model.update { $0.mahjongVariant = String(value.prefix(mahjongVariantMaxLength)) } }),
                prompt: Text("create_mahjong_variant_placeholder")
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("create_mahjong_variant_presets").font(.subheadline).foregroundStyle(.secondary)
                PulsoFlowLayout(spacing: 8) {
                    ForEach(MahjongVariantPreset.allCases, id: \.self) { preset in
                        let label = String(localized: preset.labelResource)
                        let selected = draft.mahjongVariant.trimmingCharacters(in: .whitespaces) == label
                        Button { model.update { $0.mahjongVariant = label } } label: {
                            Text(verbatim: label)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        } header: {
            Label("create_mahjong_variant_label", systemImage: "dice")
        }
        .disabled(model.isSubmitting)
    }
}
