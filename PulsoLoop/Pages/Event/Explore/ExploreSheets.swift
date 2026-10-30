import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 地图筛选（Android `ExploreFilterSheet`，WEB ExploreSidebar → Filters）：运动、关键词，然后「筛选活动」「筛选球馆」两段。
 * 两段和活动 / 球馆列表共用同一份已保存的筛选；地图按视野取范围，所以不显示距离和排序。改了马上生效。
 */
struct ExploreFilterSheet: View {
    @Bindable var model: ExploreModel
    @State private var group = ExploreFilterGroup.events

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $group) {
                        ForEach(ExploreFilterGroup.allCases, id: \.self) { option in
                            Text(verbatim: groupLabel(option)).tag(option)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                // 一次只显示一组，免得活动和球馆的筛选混在一起看错。
                switch group {
                case .events:
                    Section("explore_filter_sport") {
                        ExploreSportChipRow(selected: model.sport, glass: false) { model.selectSport($0) }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        Toggle("explore_filter_sport_row", isOn: Binding(get: { model.sportRowVisible }, set: { model.setSportRowVisible($0) }))
                    }
                    Section("explore_filter_search") {
                        TextField("explore_filter_search_hint", text: $model.search)
                    }
                    eventSection
                case .venues:
                    venueSection
                }
            }
            .navigationTitle("explore_filter_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("explore_filter_reset") { model.resetFilters() }
                        .disabled(model.filterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /** 切换上带着这一组启用的筛选数。 */
    private func groupLabel(_ option: ExploreFilterGroup) -> String {
        let count = option == .events ? (model.search.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1) + model.eventFilters.mapActiveCount : model.venueFilters.mapActiveCount
        let name = String(localized: option.labelResource)
        return count > 0 ? localizedFormat("explore_filter_group_count", name, count) : name
    }

    private var eventFilters: Binding<EventNearbyFilters> {
        Binding(get: { model.eventFilters }, set: { model.updateEventFilters($0) })
    }

    private var venueFilters: Binding<VenueNearbyFilters> {
        Binding(get: { model.venueFilters }, set: { model.updateVenueFilters($0) })
    }

    @ViewBuilder
    private var eventSection: some View {
        Section("nearby_filter_title") {
            Picker(selection: eventFilters.datePreset) {
                ForEach(EventDatePreset.allCases, id: \.self) { Text($0.labelKey).tag($0) }
            } label: {
                Label("nearby_filter_date", systemImage: "calendar")
            }
            if model.eventFilters.datePreset == .custom {
                DatePicker("nearby_filter_date_from", selection: instant(eventFilters.customFrom))
                DatePicker("nearby_filter_date_to", selection: instant(eventFilters.customTo))
            }
            Picker(selection: eventFilters.priceCap) {
                ForEach(EventPriceCap.allCases, id: \.self) { Text(verbatim: eventPriceText($0)).tag($0) }
            } label: {
                Label("nearby_filter_price", systemImage: "dollarsign.circle")
            }
            Toggle(isOn: eventFilters.openSpotsOnly) { Label("nearby_filter_open_spots", systemImage: "person.2") }
            Toggle(isOn: eventFilters.includeEnded) { Label("nearby_filter_include_ended", systemImage: "clock.arrow.circlepath") }
        }
    }

    @ViewBuilder
    private var venueSection: some View {
        Section("nearby_filter_venue_title") {
            Picker(selection: venueFilters.hourlyCap) {
                ForEach(VenueHourlyCap.allCases, id: \.self) { cap in
                    Text(verbatim: cap.max.map { localizedFormat("nearby_filter_price_upto", String(Int($0))) } ?? String(localized: "nearby_filter_price_any")).tag(cap)
                }
            } label: {
                Label("nearby_filter_hourly", systemImage: "dollarsign.circle")
            }
            NavigationLink {
                AmenityPicker(selection: venueFilters.amenities)
            } label: {
                LabeledContent {
                    Text(verbatim: model.venueFilters.amenities.isEmpty ? "" : "\(model.venueFilters.amenities.count)")
                } label: {
                    Label("nearby_filter_amenities", systemImage: "house")
                }
            }
            Toggle(isOn: venueFilters.openNow) {
                Label {
                    Text("nearby_filter_open_now")
                    Text("nearby_filter_open_now_hint")
                } icon: {
                    Image(systemName: "clock")
                }
            }
            Toggle(isOn: venueFilters.acceptsMembership) { Label("nearby_filter_accepts_membership", systemImage: "person.text.rectangle") }
            Toggle(isOn: venueFilters.acceptsPlatform) { Label("nearby_filter_accepts_platform", systemImage: "calendar.badge.checkmark") }
        }
    }

    /** RFC3339 字段 ↔ DatePicker；空串时用现在。 */
    private func instant(_ binding: Binding<String>) -> Binding<Date> {
        Binding(
            get: { DateTimeFormatters.parseInstant(binding.wrappedValue) ?? .now },
            set: { binding.wrappedValue = DateTimeFormatters.rfc3339($0) }
        )
    }

    private func eventPriceText(_ cap: EventPriceCap) -> String {
        switch cap {
        case .any: String(localized: "nearby_filter_price_any")
        case .free: String(localized: "nearby_filter_price_free")
        default: localizedFormat("nearby_filter_price_upto", String(Int(cap.max ?? 0)))
        }
    }
}

/** 设施多选：点一行勾选 / 取消。 */
private struct AmenityPicker: View {
    @Binding var selection: Set<VenueAmenityPreset>

    var body: some View {
        List(VenueAmenityPreset.allCases, id: \.self) { amenity in
            Button {
                if selection.contains(amenity) { selection.remove(amenity) } else { selection.insert(amenity) }
            } label: {
                HStack {
                    Label(amenity.labelKey, systemImage: amenity.systemImage).foregroundStyle(Color.primary)
                    Spacer()
                    if selection.contains(amenity) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
        }
        .navigationTitle("nearby_filter_amenities")
    }
}

private struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(role: .confirm) { dismiss() } label: { Image(systemName: "checkmark") }
    }
}

/**
 * 侧边按钮以外的地图设置（Android `ExploreMapSettingsSheet`）：平面 / 立体、搜索范围、活动 / 球馆卡片四块；
 * 上拉到全屏还有图层开关和球馆搜索距离。
 */
struct ExploreMapSettingsSheet: View {
    let model: ExploreModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        tile("map", label: "explore_toggle_flat", selected: model.map.mapflat) { model.toggleMapFlat() }
                        tile("dot.radiowaves.left.and.right", label: "explore_toggle_range", selected: model.map.mapNearbyRange) { model.toggleMapNearbyRange() }
                        tile("ticket", label: "explore_toggle_event_cards", selected: model.showEventCards) { model.toggleShowEventCards() }
                        tile("storefront", label: "explore_toggle_venue_cards", selected: model.showVenueCards) { model.toggleShowVenueCards() }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                }
                Section("explore_layers_title") {
                    Toggle("explore_layers_events", isOn: Binding(get: { model.layers.showEventLayer }, set: { model.setShowEventLayer($0) }))
                    Toggle("explore_layers_venues", isOn: Binding(get: { model.layers.showVenueLayer }, set: { model.setShowVenueLayer($0) }))
                    Toggle("explore_layers_tournaments", isOn: Binding(get: { model.layers.showTournamentLayer }, set: { model.setShowTournamentLayer($0) }))
                }
                if model.layers.showVenueLayer {
                    radiusSection
                }
            }
            .navigationTitle("explore_map_settings_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { DoneButton() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var radiusSection: some View {
        Section {
            Picker(selection: Binding(get: { model.layers.venueRadiusMode }, set: { model.setVenueRadiusMode($0) })) {
                Text("explore_layers_mode_multiplier").tag(VenueRadiusMode.multiplier)
                Text("explore_layers_mode_fixed").tag(VenueRadiusMode.fixed)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            switch model.layers.venueRadiusMode {
            case .multiplier:
                Picker(selection: Binding(get: { model.layers.venueRadiusMultiplier }, set: { model.setVenueRadiusMultiplier($0) })) {
                    ForEach(venueRadiusMultiplierOptions, id: \.self) { option in
                        Text(verbatim: localizedFormat("explore_layers_times", formatMultiplier(option))).tag(option)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            case .fixed:
                Picker(selection: Binding(get: { model.layers.venueRadiusFixedKm }, set: { model.setVenueRadiusFixedKm($0) })) {
                    ForEach(venueRadiusFixedKmOptions, id: \.self) { km in
                        Text(verbatim: localizedFormat("explore_layers_km", String(km))).tag(km)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("explore_layers_radius_title")
        } footer: {
            Text(verbatim: model.layers.venueRadiusMode == .multiplier
                ? localizedFormat("explore_layers_multiplier_hint", formatMultiplier(model.layers.venueRadiusMultiplier))
                : localizedFormat("explore_layers_fixed_hint", String(model.layers.venueRadiusFixedKm)))
        }
    }

    private func tile(_ systemImage: String, label: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title2)
                Text(label).font(.caption).multilineTextAlignment(.center).lineLimit(2)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(selected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func formatMultiplier(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
