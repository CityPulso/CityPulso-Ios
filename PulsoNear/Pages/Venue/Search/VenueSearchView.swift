import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 附近门店（Android `VenueSearchScreen`）：系统搜索框 + 位置 + 筛选，活动类型标签，每个标签一页可左右滑的门店卡片。 */
struct VenueSearchView: View {
    @State private var model = VenueSearchModel()
    @State private var search = ""
    @State private var filtersOpen = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        TabView(selection: Binding(get: { model.page }, set: { model.selectPage($0) })) {
            ForEach(VenueSearchModel.tabs.indices, id: \.self) { index in
                page(index).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) { tabs }
        .navigationTitle("shell_dest_venue_search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: Text("shell_venue_search_hint"))
        .onChange(of: search) { _, value in model.onSearchChange(value) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: NearRoute.locationPick) {
                    Label { Text(verbatim: model.searches[model.page].location?.label ?? "") } icon: { Image(systemName: "location.fill") }
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { filtersOpen = true } label: { Label("nearby_filter_venue_title", systemImage: "line.3.horizontal.decrease") }
                    .badge(model.filters.activeCount)
            }
        }
        .sheet(isPresented: $filtersOpen) {
            VenueFilterSheet(filters: model.filters) { model.store($0) }
        }
        .task { await model.observe() }
    }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VenueSearchModel.tabs.indices, id: \.self) { index in
                        let activityType = VenueSearchModel.tabs[index]
                        let selected = index == model.page
                        Button {
                            withAnimation { model.selectPage(index) }
                        } label: {
                            HStack(spacing: 4) {
                                if let activityType { Image(activityType.iconAsset).resizable().frame(width: 18, height: 18) }
                                if let activityType { Text(activityType.labelKey) } else { Text("nearby_filter_all_activity_types") }
                            }
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .capsule)
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .onChange(of: model.page) { _, page in withAnimation { proxy.scrollTo(page, anchor: .center) } }
        }
        .background(.bar)
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        let activityType = VenueSearchModel.tabs[index]
        let search = model.searches[index]
        if !VenueSearchModel.venuesAvailable(activityType), let activityType {
            PulsoComingSoonView(title: activityType.labelKey, systemImage: "hourglass")
        } else if let items = search.results.data, !items.isEmpty {
            List {
                ForEach(items, id: \.id) { pin in
                    NavigationLink(value: NearRoute.venue(venueId: pin.id)) {
                        NearbyVenueCard(
                            pin: pin,
                            imageURL: model.imageURL(pin.coverImageId),
                            favorited: model.favoriteIds.map { $0.contains(pin.id) }
                        ) {
                            Task { await model.toggleFavorite(pin.id) }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("search_show_on_map_cd", systemImage: "map") {
                            if model.focusOnMap(pin) { shell?.open(.explore) }
                        }
                        .tint(.accentColor)
                    }
                    .onAppear {
                        if pin.id == items.last?.id { search.loadNextPage() }
                    }
                }
                if search.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh(index) }
            .task(id: items.map(\.id)) { await model.refreshFavorites() }
        } else if search.results.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = search.results.error {
            PulsoLoadErrorView(error) { Task { await model.refresh(index) } }
        } else {
            ContentUnavailableView {
                Label("shell_venue_search_empty", systemImage: "building.2")
            } description: {
                Text("shell_venue_search_empty_hint")
            } actions: {
                Button("venue_detail_back_to_explore") { shell?.open(.explore) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/**
 * 附近门店卡片（Android `NearbyVenueCard`）：封面、名字、地址 · 距离、营业中到几点 / 已打烊、各活动类型、起步价，右上角收藏星。
 */
struct NearbyVenueCard: View {
    let pin: NearbyVenuePin
    let imageURL: URL?
    /** nil = 不显示星（没登录或没读到）。 */
    let favorited: Bool?
    let onToggleFavorite: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityTypeCover(url: imageURL, activityType: pin.activityTypes.first?.kind ?? .boardGame)
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(verbatim: pin.displayName).font(.headline).lineLimit(2)
                    Spacer(minLength: 4)
                    if let favorited {
                        Button(action: onToggleFavorite) {
                            Image(systemName: favorited ? "heart.fill" : "heart").foregroundStyle(favorited ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: localizedFormat(favorited ? "favorites_remove_named" : "favorites_add_named", pin.displayName)))
                    }
                }
                Text(verbatim: [pin.displayAddress.isEmpty ? nil : pin.displayAddress, distanceLabel(pin.distanceM)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(verbatim: openLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pin.isOpenNow ? RadixScale.green.lightStep(9) : Color.secondary)
                if !pin.activityTypes.isEmpty {
                    PulsoFlowLayout(spacing: 4) {
                        ForEach(pin.activityTypes, id: \.self) { ActivityTypeTag(activityType: $0.kind) }
                    }
                }
                if let price = venuePriceLabel(pin, locale: locale) {
                    Text(verbatim: price).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var openLine: String {
        if pin.isOpenNow, case let .open(closesAt)? = venueOpenStatus(venueWeek(pin.hours), timezone: pin.timezone) {
            return localizedFormat("nearby_venue_open_until", closesAt)
        }
        return String(localized: "nearby_venue_closed")
    }
}

/** 附近门店的筛选（Android `VenueFilterPanel`，列表里有距离和排序）：在草稿上改，点「应用」生效。 */
struct VenueFilterSheet: View {
    let filters: VenueNearbyFilters
    let onApply: (VenueNearbyFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = VenueNearbyFilters()

    var body: some View {
        NavigationStack {
            Form {
                Picker(selection: $draft.distance) {
                    ForEach(NearbyDistance.allCases, id: \.self) { distance in
                        Text(verbatim: distance.km.map { localizedFormat("nearby_filter_distance_km", $0) } ?? String(localized: "nearby_filter_distance_any")).tag(distance)
                    }
                } label: {
                    Label("nearby_filter_distance", systemImage: "location.circle")
                }
                Picker(selection: $draft.hourlyCap) {
                    ForEach(VenueHourlyCap.allCases, id: \.self) { cap in
                        Text(verbatim: cap.max.map { localizedFormat("nearby_filter_price_upto", String(Int($0))) } ?? String(localized: "nearby_filter_price_any")).tag(cap)
                    }
                } label: {
                    Label("nearby_filter_hourly", systemImage: "dollarsign.circle")
                }
                Section("nearby_filter_amenities") {
                    ForEach(VenueAmenityPreset.allCases, id: \.self) { amenity in
                        Toggle(isOn: Binding(
                            get: { draft.amenities.contains(amenity) },
                            set: { on in if on { draft.amenities.insert(amenity) } else { draft.amenities.remove(amenity) } }
                        )) {
                            Label(amenity.labelKey, systemImage: amenity.systemImage)
                        }
                    }
                }
                Section {
                    Toggle(isOn: $draft.openNow) {
                        Label {
                            Text("nearby_filter_open_now")
                            Text("nearby_filter_open_now_hint")
                        } icon: {
                            Image(systemName: "clock")
                        }
                    }
                    Toggle(isOn: $draft.acceptsMembership) { Label("nearby_filter_accepts_membership", systemImage: "person.text.rectangle") }
                    Toggle(isOn: $draft.acceptsPlatform) { Label("nearby_filter_accepts_platform", systemImage: "calendar.badge.checkmark") }
                }
                Picker(selection: $draft.sort) {
                    ForEach(VenueNearbySort.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                } label: {
                    Label("nearby_filter_sort", systemImage: "arrow.up.arrow.down")
                }
            }
            .navigationTitle("nearby_filter_venue_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("nearby_filter_reset") { draft = VenueNearbyFilters() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onApply(draft)
                        dismiss()
                    } label: {
                        draft.activeCount > 0 ? Text(verbatim: localizedFormat("nearby_filter_apply_count", draft.activeCount)) : Text("nearby_filter_apply")
                    }
                }
            }
        }
        .onAppear { draft = filters }
        .presentationDetents([.medium, .large])
    }
}
