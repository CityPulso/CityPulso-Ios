import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 地图设置（Android `MapSettingsScreen`）：地图样式、定位标记两个入口。 */
struct MapSettingsView: View {
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("map_settings_subtitle").font(.subheadline).foregroundStyle(palette.secondaryText)
                PulsoSection {
                    NavigationLink(value: NearRoute.mapStyle) {
                        PulsoSectionRow("map_style_title", systemImage: "square.3.layers.3d", supporting: String(localized: "map_style_desc"))
                    }
                    .buttonStyle(.pulsoRow)
                    NavigationLink(value: NearRoute.locationMarker) {
                        PulsoSectionRow("location_marker_title", systemImage: "location.circle", supporting: String(localized: "location_marker_desc"))
                    }
                    .buttonStyle(.pulsoRow)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("map_settings_title")
    }
}

/** 地图样式（Android `MapStyleViewModel` / `MapStyleScreen`）：浅色 / 深色样式、3D 建筑、平面、范围圈、活动 / 门店卡片；改了马上同步到账号。 */
struct MapStyleView: View {
    @State private var map = ResolvedMapPreference()
    @Environment(\.pulsoPalette) private var palette
    @Injected(\.preferenceService) private var preferenceService
    @Injected(\.deviceLocationStore) private var deviceLocation

    var body: some View {
        let center = deviceLocation.location.value?.point
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("map_style_desc").font(.subheadline).foregroundStyle(palette.secondaryText)
                NearMapView(
                    map: map,
                    initialCenter: (center?.latitude ?? MapConstants.fallbackCenter.latitude, center?.longitude ?? MapConstants.fallbackCenter.longitude),
                    initialZoom: 15
                )
                .allowsHitTesting(false)
                .frame(height: 220)
                .clipShape(palette.cardShape)
                PulsoCard {
                    VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                        PulsoSectionTitle("map_style_light_section")
                        PulsoSegmentedControl([MapLightColor.positron, .bright, .liberty], selection: binding(\.mapLightStyle)) { style in
                            switch style {
                            case .positron: Text("map_style_positron")
                            case .bright: Text("map_style_bright")
                            default: Text("map_style_liberty")
                            }
                        }
                        PulsoSectionTitle("map_style_dark_section")
                        PulsoSegmentedControl([MapDarkColor.dark, .fiord], selection: binding(\.mapDarkStyle)) { style in
                            style == .dark ? Text("map_style_dark") : Text("map_style_fiord")
                        }
                    }
                    .padding(PulsoSpace.s5)
                }
                PulsoSection {
                    toggleRow("map_style_enable_3d", supporting: "map_style_preview_3d", isOn: binding(\.map3d))
                    toggleRow("map_style_enable_flat", supporting: "map_style_preview_top", isOn: binding(\.mapflat))
                    toggleRow("map_style_enable_nearby", supporting: "map_style_enable_nearby_hint", isOn: binding(\.mapNearbyRange))
                    toggleRow("map_style_activity_cards", supporting: "map_style_activity_cards_hint", isOn: Binding(get: { map.showEventCards == true }, set: { value in save { $0.map.showEventCards = value } }))
                    toggleRow("map_style_venue_cards", supporting: "map_style_venue_cards_hint", isOn: Binding(get: { map.showVenueCards == true }, set: { value in save { $0.map.showVenueCards = value } }))
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("map_style_title")
        .task {
            for await preference in preferenceService.preference.values() {
                map = preference.map
            }
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, supporting: String.LocalizationValue, isOn: Binding<Bool>) -> some View {
        PulsoSectionRow(title, supporting: String(localized: supporting), showChevron: false) {
            Toggle(isOn: isOn) { EmptyView() }.labelsHidden()
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
    @Environment(\.pulsoPalette) private var palette
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
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("location_marker_desc").font(.subheadline).foregroundStyle(palette.secondaryText)
                PulsoCard {
                    ExploreMyLocationPin(map: previewMap, displayName: displayName, avatarURL: avatarURL) {}
                        .scaleEffect(1.6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
                PulsoCard {
                    VStack(spacing: PulsoSpace.s4) {
                        colorRow("location_marker_ring", \.ring)
                        colorRow("location_marker_dot", \.dot)
                        colorRow("location_marker_border", \.border)
                    }
                    .padding(PulsoSpace.s5)
                }
                PulsoCard {
                    VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                        PulsoSectionTitle("location_marker_badge_group")
                        Toggle(isOn: $draft.useAvatarImage) {
                            Text("location_marker_use_photo")
                            Text("location_marker_use_photo_hint")
                        }
                        colorRow("location_marker_badge_bg", \.badgeBg)
                        colorRow("location_marker_badge_border", \.badgeBorder)
                        HStack(spacing: PulsoSpace.s3) {
                            PulsoTextField(
                                "location_marker_letter",
                                text: Binding(get: { draft.letter }, set: { draft.letter = String($0.prefix(1)) }),
                                prompt: String(localized: "location_marker_letter_placeholder")
                            )
                            clearButton(visible: !draft.letter.isEmpty, label: "location_marker_reset_letter") { draft.letter = "" }
                        }
                    }
                    .padding(PulsoSpace.s5)
                }
                Button("location_marker_reset_all") { draft = LocationMarkerDraft() }
                    .buttonStyle(.pulso(.outline, tone: .gray, fullWidth: true))
                if draft != saved {
                    Button("location_marker_discard") { draft = saved }
                        .buttonStyle(.pulso(.soft, tone: .gray, fullWidth: true))
                }
            }
            .padding(PulsoSpace.s4)
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

    /** 一个颜色：左边色块点开系统取色器，中间可以直接填色值，右边清掉（跟随主题）。 */
    private func colorRow(_ label: LocalizedStringKey, _ path: WritableKeyPath<LocationMarkerDraft, String>) -> some View {
        HStack(spacing: PulsoSpace.s3) {
            ColorPicker(selection: Binding(
                get: { preferenceColor(draft[keyPath: path]) ?? palette.gray.step(5) },
                set: { draft[keyPath: path] = $0.hexString }
            ), supportsOpacity: false) { Text(label) }
                .labelsHidden()
            PulsoTextField(
                label, text: Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0 }),
                prompt: "#e5484d",
                hintText: draft[keyPath: path].isEmpty ? String(localized: "location_marker_following_theme") : nil
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            clearButton(visible: !draft[keyPath: path].isEmpty, label: "location_marker_reset_field") { draft[keyPath: path] = "" }
        }
    }

    private func clearButton(visible: Bool, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark").font(.title3).foregroundStyle(palette.secondaryText).frame(width: 40, height: 40) }
            .buttonStyle(.plain)
            .opacity(visible ? 1 : 0.4)
            .disabled(!visible)
            .accessibilityLabel(Text(label))
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
