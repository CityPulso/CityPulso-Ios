import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 地图设置（Android `MapSettingsScreen`）：地图样式、定位标记两个入口。 */
struct MapSettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: NearRoute.mapStyle) {
                    Label { VStack(alignment: .leading) { Text("map_style_title"); Text("map_style_desc").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "square.3.layers.3d") }
                }
                NavigationLink(value: NearRoute.locationMarker) {
                    Label { VStack(alignment: .leading) { Text("location_marker_title"); Text("location_marker_desc").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "location.circle") }
                }
            } footer: {
                Text("map_settings_subtitle")
            }
        }
        .navigationTitle("map_settings_title")
    }
}

/** 地图样式（Android `MapStyleViewModel` / `MapStyleScreen`）：浅色 / 深色样式、3D 建筑、平面、范围圈、活动 / 门店卡片；改了马上同步到账号。 */
struct MapStyleView: View {
    @State private var map = ResolvedMapPreference()
    @Injected(\.preferenceService) private var preferenceService
    @Injected(\.deviceLocationStore) private var deviceLocation

    var body: some View {
        let center = deviceLocation.location.value?.point
        List {
            Section {
                NearMapView(
                    map: map,
                    initialCenter: (center?.latitude ?? MapConstants.fallbackCenter.latitude, center?.longitude ?? MapConstants.fallbackCenter.longitude),
                    initialZoom: 15
                )
                .allowsHitTesting(false)
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Text((map.mapflat ? "map_style_preview_top" : "map_style_preview_3d") as LocalizedStringKey)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: .capsule)
                        .padding(8)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            Section("map_style_light_section") {
                Picker(selection: binding(\.mapLightStyle)) {
                    Text("map_style_positron").tag(MapLightColor.positron)
                    Text("map_style_bright").tag(MapLightColor.bright)
                    Text("map_style_liberty").tag(MapLightColor.liberty)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("map_style_dark_section") {
                Picker(selection: binding(\.mapDarkStyle)) {
                    Text("map_style_dark").tag(MapDarkColor.dark)
                    Text("map_style_fiord").tag(MapDarkColor.fiord)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Toggle("map_style_enable_3d", isOn: binding(\.map3d))
                Toggle("map_style_enable_flat", isOn: binding(\.mapflat))
                Toggle(isOn: binding(\.mapNearbyRange)) {
                    Text("map_style_enable_nearby")
                    Text("map_style_enable_nearby_hint")
                }
                Toggle(isOn: Binding(get: { map.showEventCards == true }, set: { value in save { $0.map.showEventCards = value } })) {
                    Text("map_style_activity_cards")
                    Text("map_style_activity_cards_hint")
                }
                Toggle(isOn: Binding(get: { map.showVenueCards == true }, set: { value in save { $0.map.showVenueCards = value } })) {
                    Text("map_style_venue_cards")
                    Text("map_style_venue_cards_hint")
                }
            }
        }
        .navigationTitle("map_style_title")
        .task {
            for await preference in preferenceService.preference.values() {
                map = preference.map
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<ResolvedMapPreference, T>) -> Binding<T> {
        Binding(get: { map[keyPath: path] }, set: { value in save { $0.map[keyPath: path] = value } })
    }

    private func save(_ edit: @escaping (inout ResolvedPreference) -> Void) {
        Task { await PreferenceSync.save(edit) }
    }
}

/** 定位标记的草稿（Android `LocationMarkerDraft`）；空串 = 跟随主题。 */
struct LocationMarkerDraft: Equatable {
    var ring = ""
    var dot = ""
    var border = ""
    var useAvatarImage = true
    var badgeBg = ""
    var badgeBorder = ""
    var letter = ""

    init() {}

    init(_ map: ResolvedMapPreference) {
        ring = map.locationRing ?? ""
        dot = map.locationDot ?? ""
        border = map.locationBorder ?? ""
        useAvatarImage = map.locationAvatarUseImage ?? true
        badgeBg = map.locationAvatarBg ?? ""
        badgeBorder = map.locationAvatarBorder ?? ""
        letter = map.locationAvatarChar ?? ""
    }
}

/**
 * 定位标记（Android `LocationMarkerViewModel` / `LocationMarkerScreen`）：外圈、圆点、描边、头像或字母徽章的颜色；
 * 清掉某项就跟随主题。改的是草稿，保存才写回偏好并同步。
 */
struct LocationMarkerView: View {
    @State private var saved = LocationMarkerDraft()
    @State private var draft = LocationMarkerDraft()
    @State private var loaded = false
    @State private var saving = false
    @State private var displayName: String?
    @State private var avatarURL: URL?
    @Injected(\.preferenceService) private var preferenceService
    @Injected(\.profileStore) private var profileStore
    @Injected(\.pulsoCoreConfig) private var config

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    ExploreMyLocationPin(map: previewMap, displayName: displayName, avatarURL: avatarURL) {}
                        .scaleEffect(1.6)
                        .padding(24)
                    Spacer()
                }
            } footer: {
                Text("location_marker_desc")
            }
            Section {
                colorRow("location_marker_ring", \.ring)
                colorRow("location_marker_dot", \.dot)
                colorRow("location_marker_border", \.border)
            }
            Section("location_marker_badge_group") {
                Toggle(isOn: $draft.useAvatarImage) {
                    Text("location_marker_use_photo")
                    Text("location_marker_use_photo_hint")
                }
                colorRow("location_marker_badge_bg", \.badgeBg)
                colorRow("location_marker_badge_border", \.badgeBorder)
                HStack {
                    Text("location_marker_letter")
                    Spacer()
                    TextField("location_marker_letter_placeholder", text: Binding(get: { draft.letter }, set: { draft.letter = String($0.prefix(1)) }))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    if !draft.letter.isEmpty {
                        Button { draft.letter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("location_marker_reset_letter"))
                    }
                }
            }
            Section {
                Button("location_marker_reset_all") { draft = LocationMarkerDraft() }
                if draft != saved {
                    Button("location_marker_discard", role: .destructive) { draft = saved }
                }
            }
        }
        .navigationTitle("location_marker_title")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView() } else { Text("location_marker_save") }
                }
                .disabled(draft == saved || saving)
            }
        }
        .task {
            await concurrently([
                {
                    for await preference in preferenceService.preference.values() {
                        let next = LocationMarkerDraft(preference.map)
                        if !loaded || draft == saved { draft = next }
                        saved = next
                        loaded = true
                    }
                },
                {
                    for await info in profileStore.current.values() {
                        displayName = info?.displayName
                        avatarURL = ImageURLs.image(info?.avatarImageId, base: config.apiBaseURL)
                    }
                },
            ])
        }
    }

    /** 草稿套到当前偏好上，给预览用。 */
    private var previewMap: ResolvedMapPreference {
        var map = ResolvedMapPreference()
        map.locationRing = normalizeHexColor(draft.ring)
        map.locationDot = normalizeHexColor(draft.dot)
        map.locationBorder = normalizeHexColor(draft.border)
        map.locationAvatarUseImage = draft.useAvatarImage
        map.locationAvatarBg = normalizeHexColor(draft.badgeBg)
        map.locationAvatarBorder = normalizeHexColor(draft.badgeBorder)
        map.locationAvatarChar = normalizeAvatarChar(draft.letter)
        return map
    }

    /** 一个颜色：系统取色器；有值时可以清掉（跟随主题）。 */
    private func colorRow(_ label: LocalizedStringKey, _ path: WritableKeyPath<LocationMarkerDraft, String>) -> some View {
        HStack {
            ColorPicker(selection: Binding(
                get: { preferenceColor(draft[keyPath: path]) ?? .accentColor },
                set: { draft[keyPath: path] = $0.hexString }
            ), supportsOpacity: false) {
                VStack(alignment: .leading) {
                    Text(label)
                    if draft[keyPath: path].isEmpty {
                        Text("location_marker_following_theme").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: draft[keyPath: path]).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            if !draft[keyPath: path].isEmpty {
                Button { draft[keyPath: path] = "" } label: { Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("location_marker_reset_field"))
            }
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let next = draft
        await PreferenceSync.save { preference in
            preference.map.locationRing = normalizeHexColor(next.ring)
            preference.map.locationDot = normalizeHexColor(next.dot)
            preference.map.locationBorder = normalizeHexColor(next.border)
            preference.map.locationAvatarUseImage = next.useAvatarImage
            preference.map.locationAvatarBg = normalizeHexColor(next.badgeBg)
            preference.map.locationAvatarBorder = normalizeHexColor(next.badgeBorder)
            preference.map.locationAvatarChar = normalizeAvatarChar(next.letter)
        }
    }
}

extension Color {
    /** `#rrggbb`（小写），给偏好里存。 */
    var hexString: String {
        let resolved = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
