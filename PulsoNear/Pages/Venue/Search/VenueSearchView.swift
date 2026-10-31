import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 附近门店（Android `VenueSearchScreen`）：系统搜索框 + 位置 + 筛选，活动类型标签，每个标签一页可左右滑的门店卡片。 */
struct VenueSearchView: View {
    @State private var model = VenueSearchModel()
    @State private var search = ""
    @State private var filtersOpen = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: Binding(get: { model.page }, set: { model.selectPage($0) })) {
                ForEach(VenueSearchModel.tabs.indices, id: \.self) { index in
                    page(index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("shell_dest_venue_search")
        // 底栏根页：没有顶栏（Android 同样只有状态栏底色 + 自己的搜索行）。
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onChange(of: search) { _, value in model.onSearchChange(value) }
        .sheet(isPresented: $filtersOpen) {
            VenueFilterSheet(filters: model.filters) { model.store($0) }
        }
        .task { await model.observe() }
    }

    /** 位置 / 搜索双槽 + 筛选方钮，下面活动类型标签（全部 + 各类型），跟着翻页。 */
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: PulsoSpace.s2) {
                PulsoAddressSearchBar(
                    locationLabel: model.searches[model.page].location?.label,
                    unknownLocation: Text("shell_calendar_location_unknown"),
                    search: $search,
                    searchHint: Text("shell_venue_search_hint")
                ) { shell?.push(NearRoute.locationPick) }
                Button { filtersOpen = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(palette.gray.step(12))
                        .frame(width: PulsoControlSize.compact.height, height: PulsoControlSize.compact.height)
                        .background(palette.gray.step(3), in: palette.controlShape)
                        .overlay(alignment: .topTrailing) {
                            if model.filters.activeCount > 0 {
                                Text(verbatim: "\(model.filters.activeCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, PulsoSpace.s1)
                                    .background(palette.error, in: Capsule())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("nearby_filter_venue_title"))
            }
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
            PulsoUnderlineTabRow(
                Array(VenueSearchModel.tabs.indices),
                selection: Binding(get: { model.page }, set: { page in withAnimation { model.selectPage(page) } }),
                image: { VenueSearchModel.tabs[$0].map { Image($0.iconAsset) } }
            ) { index in
                if let activityType = VenueSearchModel.tabs[index] { Text(activityType.labelKey) } else { Text("nearby_filter_all_activity_types") }
            }
        }
        .background(palette.background)
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        let activityType = VenueSearchModel.tabs[index]
        let search = model.searches[index]
        if !VenueSearchModel.venuesAvailable(activityType), let activityType {
            PulsoEmptyState(Text(activityType.labelKey), description: Text("coming_soon_subtitle"), style: .comingSoon)
        } else if let items = search.results.data, !items.isEmpty {
            ScrollView {
                LazyVStack(spacing: PulsoSpace.s2) {
                    ForEach(items, id: \.id) { pin in
                        NavigationLink(value: NearRoute.venue(venueId: pin.id)) {
                            PulsoCard {
                                NearbyVenueCard(
                                    pin: pin,
                                    imageURL: model.imageURL(pin.coverImageId),
                                    favorited: model.favoriteIds.map { $0.contains(pin.id) }
                                ) {
                                    Task { await model.toggleFavorite(pin.id) }
                                }
                                .padding(PulsoSpace.s3)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("search_show_on_map_cd", systemImage: "map") {
                                if model.focusOnMap(pin) { shell?.open(.explore) }
                            }
                        }
                        .onAppear {
                            if pin.id == items.last?.id { search.loadNextPage() }
                        }
                    }
                    if search.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, PulsoSpace.s4)
                .padding(.vertical, PulsoSpace.s2)
            }
            .refreshable { await model.refresh(index) }
            .task(id: items.map(\.id)) { await model.refreshFavorites() }
        } else if search.results.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = search.results.error {
            PulsoLoadErrorView(error) { Task { await model.refresh(index) } }
        } else {
            PulsoEmptyState(Text("shell_venue_search_empty"), description: Text("shell_venue_search_empty_hint")) {
                Button("venue_detail_back_to_explore") { shell?.open(.explore) }
                    .buttonStyle(.pulso())
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
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityTypeCover(url: imageURL, activityType: pin.activityTypes.first?.kind ?? .boardGame)
                .frame(width: 96, height: 96)
                .clipShape(palette.innerShape)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(verbatim: pin.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text).lineLimit(2)
                    Spacer(minLength: 4)
                    if let favorited {
                        Button(action: onToggleFavorite) {
                            Image(systemName: favorited ? "heart.fill" : "heart").font(.title3).foregroundStyle(favorited ? palette.error : palette.secondaryText)
                        }
                        .buttonStyle(.plain)
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
