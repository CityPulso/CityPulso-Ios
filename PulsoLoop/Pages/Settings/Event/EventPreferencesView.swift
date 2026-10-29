import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 活动偏好（对应 Android `EventPreferencesScreen`）：可见运动 + 附近拉取的条数与半径。 */
struct EventPreferencesView: View {
    @State private var model = EventPreferencesModel()

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LoopSport.allCases.filter(\.available)) { sport in
                            Label {
                                Text(sport.labelKey)
                            } icon: {
                                Image(sport.iconAsset).resizable().frame(width: 20, height: 20)
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.fill.tertiary, in: .capsule)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("event_pref_modules")
            } footer: {
                Text("event_pref_modules_hint")
            }

            Section {
                SliderRow(
                    label: "event_pref_page_size",
                    hint: Text(verbatim: localizedFormat("event_pref_page_size_hint", EventPreferenceLimits.pageSize.lowerBound, EventPreferenceLimits.pageSize.upperBound)),
                    value: model.draft.nearbyPageSize,
                    range: EventPreferenceLimits.pageSize,
                    display: "\(model.draft.nearbyPageSize)",
                    onChange: model.setPageSize
                )
                SliderRow(
                    label: "event_pref_radius_min",
                    hint: Text(verbatim: localizedFormat("event_pref_radius_min_hint", EventPreferenceLimits.radiusMinM.lowerBound, model.radiusMinUpper)),
                    value: model.draft.nearbyRadiusMinM,
                    range: EventPreferenceLimits.radiusMinM.lowerBound...max(EventPreferenceLimits.radiusMinM.lowerBound + 1, model.radiusMinUpper),
                    display: "\(model.draft.nearbyRadiusMinM) m",
                    onChange: model.setRadiusMin
                )
                SliderRow(
                    label: "event_pref_radius_max",
                    hint: Text(verbatim: localizedFormat("event_pref_radius_max_hint", EventPreferenceLimits.radiusMaxM.lowerBound, EventPreferenceLimits.radiusMaxM.upperBound)),
                    value: model.draft.nearbyRadiusMaxM,
                    range: EventPreferenceLimits.radiusMaxM,
                    display: "\(model.draft.nearbyRadiusMaxM) m",
                    onChange: model.setRadiusMax
                )
            } header: {
                Text("event_pref_fetch")
            } footer: {
                Text("event_pref_desc")
            }

            Section {
                Button("event_pref_reset", role: .destructive) { model.resetDefaults() }
            }
        }
        .navigationTitle("event_pref_title")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("event_pref_save") {
                    Task { await model.save() }
                }
                .disabled(!model.isDirty || model.saving)
            }
        }
    }
}

/** 一个整数滑块：标题、当前值、滑块、说明。 */
private struct SliderRow: View {
    let label: LocalizedStringKey
    let hint: Text
    let value: Int
    let range: ClosedRange<Int>
    let display: String
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(label) {
                Text(verbatim: display).monospacedDigit()
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            hint
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
