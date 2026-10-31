import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 活动偏好（对应 Android `EventPreferencesScreen`）：可见运动 + 附近拉取的条数与半径。 */
struct EventPreferencesView: View {
    @State private var model = EventPreferencesModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("event_pref_desc").font(.subheadline).foregroundStyle(palette.secondaryText)

                PulsoCard {
                    VStack(alignment: .leading, spacing: PulsoSpace.s2) {
                        Text("event_pref_modules").font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                        Text("event_pref_modules_hint").font(.caption).foregroundStyle(palette.secondaryText)
                        // Loop 现在开放的运动，只读（还没有可以关掉的）。
                        PulsoFlowLayout(spacing: PulsoSpace.s2) {
                            ForEach(LoopSport.allCases.filter(\.available)) { sport in
                                HStack(spacing: PulsoSpace.s1) {
                                    Image(sport.iconAsset).resizable().frame(width: 16, height: 16)
                                    Text(sport.labelKey)
                                }
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(palette.gray.step(12))
                                .padding(.horizontal, PulsoSpace.s3)
                                .padding(.vertical, PulsoSpace.s1 + 2)
                                .background(palette.gray.step(3), in: palette.controlShape)
                            }
                        }
                    }
                    .padding(PulsoSpace.s4)
                }

                PulsoCard {
                    VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                        Text("event_pref_fetch").font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
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
                    }
                    .padding(PulsoSpace.s4)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("event_pref_title")
        // 改了才出底栏：恢复默认（灰色描边）+ 保存（实心），各占一半（Android bottomBar）。
        .safeAreaInset(edge: .bottom) {
            if model.isDirty || model.saving {
                HStack(spacing: PulsoSpace.s2) {
                    Button("event_pref_reset") { model.resetDefaults() }
                        .buttonStyle(.pulso(.outline, tone: .gray, fullWidth: true))
                        .disabled(model.saving)
                    Button {
                        Task { await model.save() }
                    } label: {
                        PulsoButtonLabel("event_pref_save", loading: model.saving)
                    }
                    .buttonStyle(.pulso(fullWidth: true))
                    .disabled(!model.isDirty || model.saving)
                }
                .padding(PulsoSpace.s4)
                .background(palette.background.shadow(.drop(color: .black.opacity(0.08), radius: 4, y: -1)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.isDirty)
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
            .font(.subheadline)
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
