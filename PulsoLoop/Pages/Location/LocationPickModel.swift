import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一条地点搜索结果。 */
struct LocationSearchHit: Hashable, Sendable {
    let title: String
    let label: String
    let latitude: Double
    let longitude: Double
}

/**
 * 选点（Android `LocationPickViewModel`）：地图停在哪就选哪；能搜地点、回到我的位置、切平面 / 立体、显示搜索半径。
 * 确认时反查地名，写进附近搜索中心（[persistToExplore]）或交给调用方。
 */
@MainActor
@Observable
final class LocationPickModel {
    var query = ""
    private(set) var hits: [LocationSearchHit] = []
    private(set) var isSearching = false
    /** 搜过且请求结束（空结果时显示提示）。 */
    private(set) var searchSucceeded = false
    private(set) var searchError: String?
    private(set) var map = ResolvedMapPreference()
    private(set) var displayName: String?
    private(set) var avatarImageId: String?
    /** 设备位置（人像标记，不随拖图改）：先用上次保存的，重新定位后更新。 */
    private(set) var myLocation: PickedLocation?
    /** 开场飞到的位置：当前搜索中心，否则设备位置。 */
    private(set) var seed: PickedLocation?
    private(set) var camera: MapCameraRequest?
    /** 当前地图中心（拖图 / 搜索后更新），搜索偏好和半径圈用。 */
    private(set) var mapCenter: PickedLocation?
    private(set) var radiusM = 3000
    private(set) var cameraZoom = 13.0
    private(set) var isConfirming = false
    private(set) var isLocating = false
    /** 选了搜索结果后、地图还没再被拖动前，确认时直接用结果的地名。 */
    @ObservationIgnored private var pendingLabel: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    @ObservationIgnored @Injected(\.nearbyQueryLocationStore) private var queryLocation
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.deviceLocationBootstrap) private var bootstrap
    @ObservationIgnored @Injected(\.locationService) private var locationService
    @ObservationIgnored @Injected(\.preferenceService) private var preferenceService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init() {
        // 直接从 store 拿当前搜索中心开场，不等 GPS。
        if let start = queryLocation.current?.point ?? deviceLocation.location.value?.point {
            seedAt(start)
        }
    }

    var avatarURL: URL? { ImageURLs.image(avatarImageId, base: config.apiBaseURL) }

    /** 地图开场的中心：没有任何位置时用温哥华。 */
    var initialCenter: (latitude: Double, longitude: Double) {
        guard let seed else { return MapConstants.fallbackCenter }
        return (seed.latitude, seed.longitude)
    }

    /** 屏幕中心对应的点：地图回报过就用它，否则用开场位置。 */
    var center: PickedLocation {
        mapCenter ?? seed ?? PickedLocation(latitude: MapConstants.fallbackCenter.latitude, longitude: MapConstants.fallbackCenter.longitude)
    }

    func observe() async {
        await concurrently([
            {
                for await preference in self.preferenceService.preference.values() {
                    self.map = preference.map
                }
            },
            {
                for await info in self.profileStore.current.values() {
                    self.displayName = info?.displayName
                    self.avatarImageId = info?.avatarImageId
                }
            },
            {
                for await device in self.deviceLocation.location.values() {
                    guard let point = device?.point else { continue }
                    self.myLocation = point
                    // 第一次打开、什么位置都没存过：等到第一次定位就飞过去。
                    if self.seed == nil { self.seedAt(point) }
                }
            },
        ])
    }

    private func seedAt(_ point: PickedLocation) {
        seed = point
        mapCenter = point
        camera = MapCameraRequest(id: (camera?.id ?? 0) + 1, latitude: point.latitude, longitude: point.longitude, zoom: cameraZoom.clamped(to: 11 ... 16))
    }

    func onCameraIdle(_ idle: MapCameraIdle) {
        let moved = mapCenter.map { abs($0.latitude - idle.latitude) > 1e-6 || abs($0.longitude - idle.longitude) > 1e-6 } ?? true
        if moved { pendingLabel = nil }
        mapCenter = PickedLocation(latitude: idle.latitude, longitude: idle.longitude)
        radiusM = idle.radiusM
        cameraZoom = idle.zoom
    }

    /** 只改字，不自动搜（和 WEB 一样）。 */
    func onQueryChange() {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            hits = []
            searchSucceeded = false
            searchError = nil
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        query = ""
        hits = []
        isSearching = false
        searchSucceeded = false
        searchError = nil
    }

    func toggleFlat() {
        let next = !map.mapflat
        Task { await PreferenceSync.save { $0.map.mapflat = next } }
    }

    func toggleRange() {
        let next = !map.mapNearbyRange
        Task { await PreferenceSync.save { $0.map.mapNearbyRange = next } }
    }

    /** 回到我的位置：先飞到保存的位置，再重新定位、存下来，飞过去。 */
    func relocate() async {
        guard !isLocating else { return }
        if let myLocation { flyTo(myLocation) }
        isLocating = true
        defer { isLocating = false }
        if let fresh = await bootstrap.refresh() { flyTo(fresh) }
    }

    private func flyTo(_ point: PickedLocation, zoom: Double? = nil) {
        mapCenter = point
        camera = MapCameraRequest(id: (camera?.id ?? 0) + 1, latitude: point.latitude, longitude: point.longitude, zoom: zoom ?? cameraZoom.clamped(to: 11 ... 16))
    }

    /** 选一条搜索结果：飞过去，确认时用结果的地名。 */
    func pick(_ hit: LocationSearchHit) {
        guard hit.latitude.isFinite, hit.longitude.isFinite, (-90 ... 90).contains(hit.latitude), (-180 ... 180).contains(hit.longitude) else { return }
        flyTo(PickedLocation(latitude: hit.latitude, longitude: hit.longitude), zoom: 15)
        pendingLabel = hit.label.isEmpty ? hit.title : hit.label
        clearSearch()
    }

    /** 点「搜索」才请求；以地图中心（或我的位置、搜索中心）为偏好。 */
    func submitSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !text.isEmpty else {
            clearSearch()
            return
        }
        let bias = mapCenter ?? myLocation ?? queryLocation.current?.point
            ?? PickedLocation(latitude: MapConstants.fallbackCenter.latitude, longitude: MapConstants.fallbackCenter.longitude)
        isSearching = true
        searchError = nil
        searchSucceeded = false
        searchTask = Task {
            do {
                let output = try await locationService.searchLocation(query: text, lat: bias.latitude, lng: bias.longitude)
                guard !Task.isCancelled else { return }
                hits = (output.resultItems ?? []).compactMap { item in
                    guard let position = item.resolvedPositionLngLat else { return nil }
                    let label = item.resolvedLabel.isEmpty ? text : item.resolvedLabel
                    let title = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? label
                    return LocationSearchHit(title: title, label: label, latitude: position.latitude, longitude: position.longitude)
                }
                isSearching = false
                searchSucceeded = true
            } catch {
                guard !Task.isCancelled else { return }
                isSearching = false
                hits = []
                searchError = UiError(error).text(fallback: String(localized: "location_search_failed"))
            }
        }
    }

    /**
     * 确认屏幕中心：有搜索结果的地名就用它，否则反查；[persistToExplore] 时写进附近搜索中心，再交给 [onPicked]。
     */
    func confirm(persistToExplore: Bool, onPicked: ((Double, Double, String) -> Void)?) async -> Bool {
        guard !isConfirming else { return false }
        isConfirming = true
        defer { isConfirming = false }
        let location = center
        let label: String
        if let pendingLabel, !pendingLabel.isEmpty {
            label = pendingLabel
        } else {
            label = await reverseLabel(location)
        }
        if persistToExplore { queryLocation.set(location, label: label) }
        onPicked?(location.latitude, location.longitude, label)
        return true
    }

    /** 反查只是给点起个名字；失败就用坐标。 */
    private func reverseLabel(_ location: PickedLocation) async -> String {
        let item = try? await locationService.reverseGeocode(lat: location.latitude, lng: location.longitude).resultItems?.first
        if let label = item?.address?.label, !label.isEmpty { return label }
        if let title = item?.title, !title.isEmpty { return title }
        return String(format: "%.4f, %.4f", location.latitude, location.longitude)
    }
}
