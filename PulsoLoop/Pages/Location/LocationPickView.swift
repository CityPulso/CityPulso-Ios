import CoreLocation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选点页（Android `LocationPickScreen`）：地图和 Explore 一样（样式、3D 建筑、倾斜、工具、我的位置），不画活动；
 * 屏幕中心固定一根选点针。顶部搜地点，左下角地图工具，底部确认。
 * [persistToExplore] 为 true 时把结果写进附近搜索中心；[onPicked] 拿到坐标和地名；确认后调 [onConfirmed]。
 */
struct LocationPickView: View {
    var persistToExplore = true
    /** 作为弹层打开时左上角放关闭（推进来的页面用系统返回）。 */
    var showsClose = false
    var confirmText: LocalizedStringKey = "shell_location_pick_confirm"
    var onPicked: ((Double, Double, String) -> Void)?
    var onConfirmed: () -> Void = {}

    @State private var model = LocationPickModel()
    @State private var projection = LoopMapProjection()
    @State private var toolsExpanded = false
    @State private var locationManager = CLLocationManager()
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LoopMapView(
                map: model.map,
                initialCenter: model.initialCenter,
                initialZoom: model.cameraZoom,
                camera: model.camera,
                ranges: [MapRange(
                    source: "location-pick-range", layer: "location-pick-range-layer", hex: "#3B82F6",
                    visible: model.map.mapNearbyRange, latitude: model.center.latitude, longitude: model.center.longitude, radiusM: model.radiusM
                )],
                projection: projection,
                onIdle: { model.onCameraIdle($0) },
                onTap: {
                    toolsExpanded = false
                    searchFocused = false
                }
            )
            .overlay {
                // 和地图同一个坐标系：标记按投影位置放，选点针在地图正中。
                ZStack {
                    myLocationMarker
                    Image(systemName: "mappin")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .shadow(radius: 2)
                        .offset(y: -20)
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top) { searchPanel }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                mapTools
                Button {
                    Task {
                        if await model.confirm(persistToExplore: persistToExplore, onPicked: onPicked) {
                            onConfirmed()
                            dismiss()
                        }
                    }
                } label: {
                    Group { if model.isConfirming { ProgressView() } else { Text(confirmText) } }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(model.isConfirming)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(Text("shell_location_pick_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .task { await model.observe() }
    }

    /** 我的位置：头像在定位圈上（Android `LocationPickMyLocation`），跟着地图移动。 */
    @ViewBuilder
    private var myLocationMarker: some View {
        let _ = projection.version
        if let me = model.myLocation, let point = projection.point(latitude: me.latitude, longitude: me.longitude) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 56, height: 56)
                PulsoAvatar(url: model.map.locationAvatarUseImage == false ? nil : model.avatarURL, size: 32, systemImage: "person.fill", fallbackText: model.displayName)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
            .position(point)
        }
    }

    private var searchPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("shell_location_search_hint", text: $model.query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit { model.submitSearch() }
                        .onChange(of: model.query) { model.onQueryChange() }
                    if model.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                if searchFocused || !model.query.isEmpty {
                    Button("shell_location_search_cancel") {
                        model.clearSearch()
                        searchFocused = false
                    }
                    .buttonStyle(.glass)
                }
            }
            if model.isSearching || model.searchSucceeded || !model.hits.isEmpty || model.searchError != nil {
                results
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching {
            Text("explore_address_searching").font(.subheadline).foregroundStyle(.secondary)
        } else if let error = model.searchError {
            Text(verbatim: error).font(.subheadline).foregroundStyle(.red)
        } else if model.hits.isEmpty {
            Text("shell_location_search_empty").font(.subheadline).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.hits.indices, id: \.self) { index in
                        let hit = model.hits[index]
                        Button {
                            model.pick(hit)
                            searchFocused = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: hit.title).font(.body.weight(.medium)).lineLimit(1)
                                if !hit.label.isEmpty, hit.label != hit.title {
                                    Text(verbatim: hit.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < model.hits.count - 1 { Divider() }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    /** 左下角的地图工具（和 Explore 同款，没有「发起」）：展开后有回到我的位置、平面 / 立体、搜索半径。 */
    private var mapTools: some View {
        VStack(alignment: .leading, spacing: 8) {
            if toolsExpanded {
                toolButton(model.isLocating ? "location.fill" : "location", selected: false, label: "location_pick_relocate") { relocate() }
                toolButton("map", selected: model.map.mapflat, label: "explore_toggle_flat") { model.toggleFlat() }
                toolButton("dot.radiowaves.left.and.right", selected: model.map.mapNearbyRange, label: "explore_toggle_range") { model.toggleRange() }
            }
            toolButton(toolsExpanded ? "xmark" : "square.3.layers.3d", selected: false, label: toolsExpanded ? "explore_map_tools_collapse_cd" : "explore_map_tools_expand_cd") {
                withAnimation(.snappy) { toolsExpanded.toggle() }
            }
        }
    }

    private func toolButton(_ systemImage: String, selected: Bool, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
    }

    /** 第一次点会先要定位权限；给了就直接重新定位。 */
    private func relocate() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            Task {
                // 等用户在系统弹窗里选完（最多 30 秒）。
                for _ in 0 ..< 60 where locationManager.authorizationStatus == .notDetermined {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if [.authorizedAlways, .authorizedWhenInUse].contains(locationManager.authorizationStatus) {
                    await model.relocate()
                }
            }
        case .authorizedAlways, .authorizedWhenInUse:
            Task { await model.relocate() }
        default:
            break
        }
    }
}
