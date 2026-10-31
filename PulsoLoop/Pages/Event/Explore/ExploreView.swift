import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * Explore 地图（Android `ExploreScreen`）：针和我的位置叠在地图上，顶栏是地址搜索 + 筛选 + 地图设置，
 * 第二行选运动；右侧地图工具；点针后底部面板显示一张卡，上拉看附近列表。选了运动时活动和球馆改用自己的预览卡。
 */
struct ExploreView: View {
    @State private var model = ExploreModel()
    @State private var projection = LoopMapProjection()
    @State private var filtersOpen = false
    @State private var mapSettingsOpen = false
    /** 页面在屏幕上（推进别的页面时面板先收起，回来再弹出）。 */
    @State private var isVisible = false
    @FocusState private var addressFocused: Bool
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    private static let eventRangeHex = "#3B82F6"
    private static let venueRangeHex = "#F59E0B"

    var body: some View {
        ZStack {
            LoopMapView(
                map: model.map,
                initialCenter: (model.centerLat, model.centerLng),
                initialZoom: model.cameraZoom,
                camera: model.camera,
                ranges: ranges,
                projection: projection,
                onIdle: { model.onCameraIdle($0) },
                onTap: { addressFocused = false },
                onLongPress: { lat, lng in push(.markPlace(latitude: lat, longitude: lng)) },
                onGestureMove: { model.clearSelection() },
                onStyleReady: { model.onMapReady() }
            )
            .overlay {
                ExplorePinsOverlay(model: model, projection: projection, onOpenEvent: { openEvent($0) }, onRoute: { push($0) }) {
                    shell?.open(.profile)
                }
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .trailing, spacing: 12) {
                ExploreTopPanel(
                    model: model,
                    addressFocused: $addressFocused,
                    onOpenFilters: { filtersOpen = true },
                    onOpenMapSettings: { mapSettingsOpen = true }
                )
                ExploreMapTools(model: model, onCreate: { shell?.open(.create) }) {
                    push(.markPlace(latitude: model.centerLat, longitude: model.centerLng))
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            ExplorePreviewCards(model: model, onOpenEvent: { openEvent($0) }, onRoute: { push($0) })
                .padding(.horizontal)
                .padding(.bottom, 8)
                .animation(.snappy, value: model.previewEvent?.id ?? model.previewVenue?.id)
        }
        .overlay(alignment: .top) {
            if model.isLoading, model.pins.isEmpty, model.venuePins.isEmpty {
                ProgressView().padding(.top, 120)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: panelShown) {
            ExplorePanelSheet(model: model, onOpenEvent: { openEvent($0) }, onRoute: { push($0) })
        }
        .sheet(isPresented: $filtersOpen) {
            ExploreFilterSheet(model: model)
        }
        .sheet(isPresented: $mapSettingsOpen) {
            ExploreMapSettingsSheet(model: model)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task { await model.observe() }
    }

    private var ranges: [MapRange] {
        [
            MapRange(
                source: "explore-range", layer: "explore-range-layer", hex: Self.eventRangeHex,
                visible: model.map.mapNearbyRange && model.layers.showEventLayer,
                latitude: model.centerLat, longitude: model.centerLng, radiusM: model.radiusM
            ),
            MapRange(
                source: "explore-venue-range", layer: "explore-venue-range-layer", hex: Self.venueRangeHex,
                visible: model.map.mapNearbyRange && (model.layers.showVenueLayer || model.layers.showTournamentLayer),
                latitude: model.centerLat, longitude: model.centerLng, radiusM: model.venueRadiusM
            ),
        ]
    }

    /** 点了针就弹出面板；选了运动时活动 / 球馆用自己的预览卡，面板让开。用户拉下面板就清掉选中。 */
    private var panelShown: Binding<Bool> {
        Binding(
            get: {
                isVisible && model.hasSelection && model.previewEvent == nil && model.previewVenue == nil && !filtersOpen && !mapSettingsOpen
            },
            set: { shown in
                if !shown, isVisible, !filtersOpen, !mapSettingsOpen { model.clearSelection() }
            }
        )
    }

    /** 活动自己的详情页（先预拉）。 */
    private func openEvent(_ pin: ExplorePin) {
        model.prefetchEventDetail(pin)
        push(.event(sport: LoopSport.fromEventType(pin.eventType), eventId: pin.id))
    }

    private func push(_ route: LoopRoute) {
        addressFocused = false
        shell?.push(route)
    }
}

/* ------------------------------ 针图层 ------------------------------ */

/** 盖在地图上的针和卡片，按投影位置摆；挨得太近的合成聚合针（Android `ExploreMapPinsOverlay`）。 */
private struct ExplorePinsOverlay: View {
    let model: ExploreModel
    let projection: LoopMapProjection
    let onOpenEvent: (ExplorePin) -> Void
    let onRoute: (LoopRoute) -> Void
    let onOpenProfile: () -> Void

    @State private var openClusterId: String?

    var body: some View {
        let _ = projection.version
        let cards = model.showEventCards || model.showVenueCards
        // 选中的针永远单独显示，其余可以合并。
        let selectedKeys = Set([
            model.selectedPinId.map { "\(ExploreMapItemKind.event):\($0)" },
            model.selectedVenueId.map { "\(ExploreMapItemKind.venue):\($0)" },
            model.selectedBuildingId.map { "\(ExploreMapItemKind.building):\($0)" },
            model.selectedTournamentId.map { "\(ExploreMapItemKind.tournament):\($0)" },
        ].compactMap { $0 })
        let points = projectedPoints
        let pinned = points.filter { selectedKeys.contains($0.0.id) }
        let grouped = clusterByScreen(points.filter { !selectedKeys.contains($0.0.id) }, radius: cards ? 120 : 40)
        let at = Dictionary(points.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
        ZStack {
            ForEach(grouped.singles + pinned.map(\.0)) { item in
                if let point = at[item.id] {
                    single(item, at: point)
                }
            }
            ForEach(grouped.clusters) { cluster in
                ExploreClusterPin(
                    cluster: cluster,
                    open: Binding(get: { openClusterId == cluster.id }, set: { openClusterId = $0 ? cluster.id : nil }),
                    eventCards: model.showEventCards,
                    venueCards: model.showVenueCards,
                    imageURL: { model.imageURL($0) }
                ) { item in
                    openClusterId = nil
                    model.select(item)
                }
                .position(cluster.center)
                .zIndex(ExploreMapLayer.selectedPin)
            }
            if model.hasMyLocation, let lat = model.myLocationLat, let lng = model.myLocationLng, let point = projection.point(latitude: lat, longitude: lng) {
                ExploreMyLocationPin(map: model.map, displayName: model.displayName, avatarURL: model.avatarURL, onTap: onOpenProfile)
                    .position(x: point.x, y: point.y - 18)
                    .zIndex(ExploreMapLayer.myLocation)
            }
        }
        // 缩放会重新分组，开着的面板会指向不存在的聚合。
        .onChange(of: model.cameraZoom) { openClusterId = nil }
    }

    private var projectedPoints: [(ExploreMapItem, CGPoint)] {
        var points: [(ExploreMapItem, CGPoint)] = []
        func add(_ item: ExploreMapItem, _ lat: Double?, _ lng: Double?) {
            guard let lat, let lng, let point = projection.point(latitude: lat, longitude: lng) else { return }
            points.append((item, point))
        }
        if model.layers.showVenueLayer {
            model.visibleBuildingPins.forEach { add(.building($0), $0.locationLat, $0.locationLng) }
            model.visibleVenuePins.forEach { add(.venue($0), $0.pinLat, $0.pinLng) }
        }
        if model.layers.showTournamentLayer {
            model.tournamentPins.forEach { add(.tournament($0), $0.lat, $0.lng) }
        }
        model.pins.forEach { add(.event($0), $0.locationLat, $0.locationLng) }
        return points
    }

    /** 不在聚合里的针，和以前一样画（卡片开着时加上卡片）。再点一次已选中的针打开它。 */
    @ViewBuilder
    private func single(_ item: ExploreMapItem, at point: CGPoint) -> some View {
        switch item {
        case let .building(building):
            let selected = building.id == model.selectedBuildingId
            ExploreBuildingPin(building: building, selected: selected) {
                selected ? onRoute(.building(buildingId: building.id)) : model.selectBuilding(building.id)
            }
            .position(point)
            .zIndex(selected ? ExploreMapLayer.selectedPin : ExploreMapLayer.venuePin)
        case let .venue(pin):
            let selected = pin.id == model.selectedVenueId
            if model.showVenueCards {
                ExploreVenuePinCard(pin: pin, imageURL: model.imageURL(pin.coverImageId), pinned: true) {
                    onRoute(.venue(venueId: pin.id))
                }
                .fixedSize()
                .position(x: point.x, y: point.y - 22 - 48)
                .zIndex(selected ? ExploreMapLayer.selectedCard : ExploreMapLayer.venueCard)
            }
            ExploreVenuePin(pin: pin, selected: selected) {
                selected ? onRoute(.venue(venueId: pin.id)) : model.selectVenue(pin.id)
            }
            .position(point)
            .zIndex(selected ? ExploreMapLayer.selectedPin : ExploreMapLayer.venuePin)
        case let .tournament(pin):
            let selected = pin.id == model.selectedTournamentId
            ExploreTournamentPin(pin: pin, selected: selected) {
                selected ? onRoute(.tournament(tournamentId: pin.tournamentId)) : model.selectTournament(pin.id)
            }
            .position(point)
            .zIndex(selected ? ExploreMapLayer.selectedPin : ExploreMapLayer.venuePin)
        case let .event(pin):
            let selected = pin.id == model.selectedPinId
            if model.showEventCards {
                ExploreEventPinCard(pin: pin, imageURL: model.imageURL(pin.imageId), pinned: true) { onOpenEvent(pin) }
                    .fixedSize()
                    .position(x: point.x, y: point.y - 18 - 36)
                    .zIndex(selected ? ExploreMapLayer.selectedCard : ExploreMapLayer.eventCard)
            }
            ExploreEventPin(pin: pin, selected: selected) {
                selected ? onOpenEvent(pin) : model.selectPin(pin.id)
            }
            .position(point)
            .zIndex(selected ? ExploreMapLayer.selectedPin : ExploreMapLayer.eventPin)
        }
    }
}

/* ------------------------------ 顶栏 ------------------------------ */

/**
 * 顶栏（Android `ExploreTopPanel`）：地址搜索框（右侧筛选按钮带角标）+ 地图设置；下面是运动选择、地址结果、加载失败重试。
 */
private struct ExploreTopPanel: View {
    @Bindable var model: ExploreModel
    var addressFocused: FocusState<Bool>.Binding
    let onOpenFilters: () -> Void
    let onOpenMapSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        searchField
                        if !model.addressQuery.isEmpty || model.addressSearchSucceeded || model.addressSearchError != nil {
                            Button("explore_address_cancel") {
                                model.clearAddressSearch()
                                addressFocused.wrappedValue = false
                            }
                            .buttonStyle(.pulso(.soft))
                            .controlSize(.large)
                        }
                    }
                    if model.isAddressSearching || model.addressSearchSucceeded || !model.addressHits.isEmpty || model.addressSearchError != nil {
                        addressResults
                    }
                }
                Button(action: {
                    addressFocused.wrappedValue = false
                    onOpenMapSettings()
                }) {
                    Image(systemName: "square.3.layers.3d").font(.title3).frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                .accessibilityLabel(Text("explore_map_settings_open_cd"))
            }
            if model.sportRowVisible {
                ExploreSportChipRow(selected: model.sport) { model.selectSport($0) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.error != nil, !model.isLoading {
                Button("explore_load_failed_retry") { model.retryNearby() }
                    .buttonStyle(.pulso(.soft))
            }
        }
        .animation(.snappy, value: model.sportRowVisible)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            TextField("explore_address_hint", text: $model.addressQuery)
                .focused(addressFocused)
                .submitLabel(.search)
                .onSubmit { model.submitAddressSearch() }
                .onChange(of: model.addressQuery) { model.onAddressQueryChange() }
            if model.isAddressSearching {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    model.submitAddressSearch()
                    addressFocused.wrappedValue = false
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(model.addressQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("explore_address_search_cd"))
            }
            Button {
                addressFocused.wrappedValue = false
                onOpenFilters()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(model.filterCount > 0 ? Color.accentColor : Color.primary)
                    .overlay(alignment: .topTrailing) {
                        if model.filterCount > 0 {
                            Text(verbatim: "\(model.filterCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(Color.accentColor, in: .capsule)
                                .offset(x: 8, y: -8)
                        }
                    }
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.pulsoPressBounce)
            .accessibilityLabel(Text("explore_filter_cd"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 48)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var addressResults: some View {
        Group {
            if model.isAddressSearching {
                Text("explore_address_searching").font(.footnote).foregroundStyle(.secondary).padding()
            } else if let error = model.addressSearchError {
                Text(verbatim: error).font(.footnote).foregroundStyle(.red).padding()
            } else if model.addressHits.isEmpty {
                Text("explore_address_empty").font(.footnote).foregroundStyle(.secondary).padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.addressHits, id: \.self) { hit in
                            Button {
                                model.selectAddressHit(hit)
                                addressFocused.wrappedValue = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: hit.title).font(.subheadline.weight(.semibold))
                                    if !hit.label.isEmpty, hit.label != hit.title {
                                        Text(verbatim: hit.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/** 运动选择：全部 + 各运动（没上线的置灰，标「即将上线」）。[glass] 浮在地图上时用玻璃底；面板里不用。 */
struct ExploreSportChipRow: View {
    let selected: LoopSport?
    var glass = true
    let onSelect: (LoopSport?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(Text("explore_sport_all"), image: nil, isOn: selected == nil, enabled: true) { onSelect(nil) }
                ForEach(LoopSport.allCases) { sport in
                    chip(
                        sport.available ? Text(sport.labelKey) : Text(verbatim: localizedFormat("explore_sport_coming_soon", String(localized: sport.labelResource))),
                        image: sport.iconAsset,
                        isOn: selected == sport,
                        enabled: sport.available
                    ) { onSelect(sport) }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(_ label: Text, image: String?, isOn: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        let content = Button(action: action) {
            HStack(spacing: 6) {
                if let image { Image(image).resizable().scaledToFit().frame(width: 18, height: 18) }
                label.font(.subheadline.weight(isOn ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? Color.accentColor : Color.clear, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        if glass {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(Color(.tertiarySystemFill), in: .capsule)
        }
    }
}

/** 右上角的地图工具（Android `ExploreMapTools`）：我的位置、活动 / 球馆 / 赛事图层、发起（球友才有）、标记地点。 */
private struct ExploreMapTools: View {
    let model: ExploreModel
    let onCreate: () -> Void
    let onMarkPlace: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                tool("location.fill", selected: false, label: "explore_recenter") { model.recenterToMyLocation() }
                tool("calendar", selected: model.layers.showEventLayer, label: "explore_layers_events") { model.setShowEventLayer(!model.layers.showEventLayer) }
                tool("building.2", selected: model.layers.showVenueLayer, label: "explore_layers_venues") { model.setShowVenueLayer(!model.layers.showVenueLayer) }
                tool("trophy", selected: model.layers.showTournamentLayer, label: "explore_layers_tournaments") { model.setShowTournamentLayer(!model.layers.showTournamentLayer) }
                if model.isPulser {
                    tool("plus", selected: false, label: "explore_create_cd", action: onCreate)
                }
                tool("mappin.and.ellipse", selected: false, label: "place_mark_action", action: onMarkPlace)
            }
        }
    }

    private func tool(_ systemImage: String, selected: Bool, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
