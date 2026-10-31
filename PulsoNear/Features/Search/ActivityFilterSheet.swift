import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动列表的筛选（对应 Android `ActivityFilterSheet` + `ActivityFilterPanel`）：在草稿上改活动类型标签和存着的筛选，
 * 点「应用」两样一起生效。系统表单。
 */
struct ActivityFilterSheet: View {
    let activityType: NearActivityKind?
    let filters: ActivityNearbyFilters
    var showDistance = true
    var showSort = true
    /** 有活动类型标签的页面才显示活动类型选择。 */
    var showsActivityType = true
    let onApply: (NearActivityKind?, ActivityNearbyFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftActivityType: NearActivityKind?
    @State private var draft = ActivityNearbyFilters()

    var body: some View {
        NavigationStack {
            Form {
                if showDistance {
                    Picker(selection: $draft.distance) {
                        ForEach(NearbyDistance.allCases, id: \.self) { distance in
                            Text(verbatim: distanceText(distance)).tag(distance)
                        }
                    } label: {
                        Label("nearby_filter_distance", systemImage: "location.circle")
                    }
                }
                Section {
                    Picker(selection: $draft.datePreset) {
                        ForEach(ActivityDatePreset.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    } label: {
                        Label("nearby_filter_date", systemImage: "calendar")
                    }
                    if draft.datePreset == .custom {
                        PulsoWheelDatePicker("nearby_filter_date_from", selection: instant(\.customFrom))
                        PulsoWheelDatePicker("nearby_filter_date_to", selection: instant(\.customTo))
                    }
                }
                Picker(selection: $draft.priceCap) {
                    ForEach(ActivityPriceCap.allCases, id: \.self) { Text(verbatim: priceText($0)).tag($0) }
                } label: {
                    Label("nearby_filter_price", systemImage: "dollarsign.circle")
                }
                if showsActivityType {
                    Picker(selection: $draftActivityType) {
                        Text("nearby_filter_all_activity_types").tag(NearActivityKind?.none)
                        ForEach(NearActivityKind.allCases) { activityType in
                            Label {
                                Text(activityType.labelKey)
                            } icon: {
                                Image(activityType.iconAsset)
                            }
                            .tag(NearActivityKind?.some(activityType))
                        }
                    } label: {
                        Label("nearby_filter_type", systemImage: "sportscourt")
                    }
                }
                Section {
                    Toggle(isOn: $draft.openSpotsOnly) { Label("nearby_filter_open_spots", systemImage: "person.2") }
                    Toggle(isOn: $draft.includeEnded) { Label("nearby_filter_include_ended", systemImage: "clock.arrow.circlepath") }
                }
                if showSort {
                    Picker(selection: $draft.sort) {
                        ForEach(ActivityNearbySort.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    } label: {
                        Label("nearby_filter_sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationTitle("nearby_filter_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("nearby_filter_reset") {
                        draft = ActivityNearbyFilters()
                        draftActivityType = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let count = draft.activeCount + (draftActivityType != nil ? 1 : 0)
                    Button(role: .confirm) {
                        onApply(draftActivityType, draft)
                        dismiss()
                    } label: {
                        count > 0 ? Text(verbatim: localizedFormat("nearby_filter_apply_count", count)) : Text("nearby_filter_apply")
                    }
                }
            }
        }
        .onAppear {
            draft = filters
            draftActivityType = activityType
        }
        .presentationDetents([.medium, .large])
    }

    /** RFC3339 字段 ↔ DatePicker；空串时用现在。 */
    private func instant(_ path: WritableKeyPath<ActivityNearbyFilters, String>) -> Binding<Date> {
        Binding(
            get: { DateTimeFormatters.parseInstant(draft[keyPath: path]) ?? .now },
            set: { draft[keyPath: path] = DateTimeFormatters.rfc3339($0) }
        )
    }

    private func distanceText(_ distance: NearbyDistance) -> String {
        distance.km.map { localizedFormat("nearby_filter_distance_km", $0) } ?? String(localized: "nearby_filter_distance_any")
    }

    private func priceText(_ cap: ActivityPriceCap) -> String {
        switch cap {
        case .any: String(localized: "nearby_filter_price_any")
        case .free: String(localized: "nearby_filter_price_free")
        default: localizedFormat("nearby_filter_price_upto", String(Int(cap.max ?? 0)))
        }
    }
}
