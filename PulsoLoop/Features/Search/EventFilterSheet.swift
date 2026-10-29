import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动列表的筛选（对应 Android `EventFilterSheet` + `EventFilterPanel`）：在草稿上改运动标签和存着的筛选，
 * 点「应用」两样一起生效。系统表单。
 */
struct EventFilterSheet: View {
    let sport: LoopSport?
    let filters: EventNearbyFilters
    var showDistance = true
    var showSort = true
    /** 有运动标签的页面才显示运动选择。 */
    var showsSport = true
    let onApply: (LoopSport?, EventNearbyFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftSport: LoopSport?
    @State private var draft = EventNearbyFilters()

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
                        ForEach(EventDatePreset.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    } label: {
                        Label("nearby_filter_date", systemImage: "calendar")
                    }
                    if draft.datePreset == .custom {
                        DatePicker("nearby_filter_date_from", selection: instant(\.customFrom))
                        DatePicker("nearby_filter_date_to", selection: instant(\.customTo))
                    }
                }
                Picker(selection: $draft.priceCap) {
                    ForEach(EventPriceCap.allCases, id: \.self) { Text(verbatim: priceText($0)).tag($0) }
                } label: {
                    Label("nearby_filter_price", systemImage: "dollarsign.circle")
                }
                if showsSport {
                    Picker(selection: $draftSport) {
                        Text("nearby_filter_all_sports").tag(LoopSport?.none)
                        ForEach(LoopSport.allCases) { sport in
                            Label {
                                Text(sport.labelKey)
                            } icon: {
                                Image(sport.iconAsset)
                            }
                            .tag(LoopSport?.some(sport))
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
                        ForEach(EventNearbySort.allCases, id: \.self) { Text($0.labelKey).tag($0) }
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
                        draft = EventNearbyFilters()
                        draftSport = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let count = draft.activeCount + (draftSport != nil ? 1 : 0)
                    Button(role: .confirm) {
                        onApply(draftSport, draft)
                        dismiss()
                    } label: {
                        count > 0 ? Text(verbatim: localizedFormat("nearby_filter_apply_count", count)) : Text("nearby_filter_apply")
                    }
                }
            }
        }
        .onAppear {
            draft = filters
            draftSport = sport
        }
        .presentationDetents([.medium, .large])
    }

    /** RFC3339 字段 ↔ DatePicker；空串时用现在。 */
    private func instant(_ path: WritableKeyPath<EventNearbyFilters, String>) -> Binding<Date> {
        Binding(
            get: { DateTimeFormatters.parseInstant(draft[keyPath: path]) ?? .now },
            set: { draft[keyPath: path] = DateTimeFormatters.rfc3339($0) }
        )
    }

    private func distanceText(_ distance: NearbyDistance) -> String {
        distance.km.map { localizedFormat("nearby_filter_distance_km", $0) } ?? String(localized: "nearby_filter_distance_any")
    }

    private func priceText(_ cap: EventPriceCap) -> String {
        switch cap {
        case .any: String(localized: "nearby_filter_price_any")
        case .free: String(localized: "nearby_filter_price_free")
        default: localizedFormat("nearby_filter_price_upto", String(Int(cap.max ?? 0)))
        }
    }
}
