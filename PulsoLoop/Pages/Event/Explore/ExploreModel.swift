import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 预览卡在地图针以外还要的：全部照片、简介和人数（Android `ExploreEventPreview`）。 */
struct ExploreEventPreview: Sendable {
    let imageIds: [String]
    let description: String?
    let capacity: Int
    let participating: Int
}

/** 地图上任意一种针，好让球馆、建筑、活动、赛事一起聚合（Android `ExploreMapItem`）。 */
enum ExploreMapItem: Identifiable, Sendable {
    case venue(NearbyVenuePin)
    case building(BuildingItem)
    case event(ExplorePin)
    case tournament(TournamentPin)

    var kind: ExploreMapItemKind {
        switch self {
        case .venue: .venue
        case .building: .building
        case .event: .event
        case .tournament: .tournament
        }
    }

    var itemId: String {
        switch self {
        case let .venue(pin): pin.id
        case let .building(building): building.id
        case let .event(pin): pin.id
        case let .tournament(pin): pin.id
        }
    }

    var id: String { "\(kind):\(itemId)" }
}

extension ExploreMapItemKind {
    /** 聚合面板里归在哪个分段。 */
    var clusterTab: ExploreClusterTab {
        switch self {
        case .event: .events
        case .tournament: .tournaments
        case .venue, .building: .venues
        }
    }
}

/**
 * Explore 地图（Android `ExploreViewModel` + `ExploreUiState` 及其 EventPins / PlaceLayers / Previews /
 * MapPreferences / AddressSearch 帮手）：视口里的活动、球馆、建筑、赛事针，筛选，地址搜索，平面 / 立体、范围圈，
 * 从搜索页聚焦过来。3D 建筑只按偏好显示，工具栏不切换。
 */
@MainActor
@Observable
final class ExploreModel {
    static let viewportDebounce = Duration.milliseconds(350)
    static let venuePageSize = 20
    static let buildingPageSize = 50

    /* ------------------------------ 状态（Android ExploreUiState） ------------------------------ */

    /** 选中活动的预览卡要的详情（选了运动时）。 */
    private(set) var eventPreview = Loadable<ExploreEventPreview>(isLoading: false)
    /** 选中球馆的照片，按顺序。 */
    private(set) var venuePreviewImageIds: [String] = []
    private(set) var centerLat = MapConstants.fallbackCenter.latitude
    private(set) var centerLng = MapConstants.fallbackCenter.longitude
    private(set) var radiusM = 5000
    private(set) var pageIndex = 0
    private(set) var pageSize = exploreNearbyPageSize
    private(set) var total = 0
    private(set) var pins: [ExplorePin] = []
    private(set) var selectedPinId: String?
    private(set) var layers = ExploreLayerSettings()
    private(set) var venuePins: [NearbyVenuePin] = []
    private(set) var buildingPins: [BuildingItem] = []
    private(set) var selectedVenueId: String?
    private(set) var selectedBuildingId: String?
    private(set) var tournamentPins: [TournamentPin] = []
    private(set) var selectedTournamentId: String?
    private(set) var isLoading = false
    private(set) var isPulser = false
    private(set) var isMapReady = false
    /** 附近活动没加载出来；地图上显示重试。 */
    private(set) var error: LoadErrorKind?
    /** nil = 全部（所有已上线运动）。 */
    private(set) var sport: LoopSport?
    /** 顶栏第二行（运动选择）是否显示。 */
    private(set) var sportRowVisible = true
    /** 地图上按活动标题搜（只在这次打开里有效，不保存）。 */
    var search = "" {
        didSet {
            guard search != oldValue else { return }
            pageIndex = 0
            sync()
        }
    }

    /** 已保存的附近活动筛选，和活动列表共用。 */
    private(set) var eventFilters = EventNearbyFilters()
    /** 已保存的附近球馆筛选，和球馆列表共用。 */
    private(set) var venueFilters = VenueNearbyFilters()
    var addressQuery = ""
    private(set) var addressHits: [LocationSearchHit] = []
    private(set) var isAddressSearching = false
    /** 点过「搜索」且请求结束（空结果时显示提示）。 */
    private(set) var addressSearchSucceeded = false
    private(set) var addressSearchError: String?
    private(set) var map = ResolvedMapPreference()
    private(set) var displayName: String?
    private(set) var avatarImageId: String?
    private(set) var myLocationLat: Double?
    private(set) var myLocationLng: Double?
    /** 最近一次相机停下时的缩放；回到 Explore 或换样式时用，不会缩成世界地图。 */
    private(set) var cameraZoom = 12.0
    private(set) var camera: MapCameraRequest?

    /* ------------------------------ 依赖与任务 ------------------------------ */

    @ObservationIgnored @Injected(\.exploreService) private var exploreService
    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.buildingService) private var buildingService
    @ObservationIgnored @Injected(\.tournamentService) private var tournamentService
    @ObservationIgnored @Injected(\.exploreLayerStore) private var layerStore
    @ObservationIgnored @Injected(\.eventNearbyFilterStore) private var eventFilterStore
    @ObservationIgnored @Injected(\.venueNearbyFilterStore) private var venueFilterStore
    @ObservationIgnored @Injected(\.preferenceService) private var preferenceService
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.deviceLocationBootstrap) private var bootstrap
    @ObservationIgnored @Injected(\.exploreFocusStore) private var focusStore
    @ObservationIgnored @Injected(\.locationService) private var locationService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let sportServices = Container.shared.loopSportServices()

    @ObservationIgnored private var session = AuthSession.loggedOut
    @ObservationIgnored private var eventRadiusRange = exploreNearbyRadiusMinM ... exploreNearbyRadiusMaxM
    @ObservationIgnored private var viewportTask: Task<Void, Never>?
    @ObservationIgnored private var addressTask: Task<Void, Never>?
    @ObservationIgnored private var eventsKey: NearbyPinsKey?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var venuesKey: VenueViewport?
    @ObservationIgnored private var venuesTask: Task<Void, Never>?
    /** 卡片 / 摘要两种针内容不同，换了或筛选变了就整组重来；只是挪地图时已有的针留着。 */
    @ObservationIgnored private var lastVenueShape: (summary: Bool, filters: VenueNearbyFilters)?
    @ObservationIgnored private var buildingsKey: VenueViewport?
    @ObservationIgnored private var buildingsTask: Task<Void, Never>?
    @ObservationIgnored private var buildingsRefresh = 0
    @ObservationIgnored private var tournamentsKey: VenueViewport?
    @ObservationIgnored private var tournamentsTask: Task<Void, Never>?
    @ObservationIgnored private var eventPreviewKey: String?
    @ObservationIgnored private var eventPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var venuePreviewKey: String?
    @ObservationIgnored private var venuePreviewTask: Task<Void, Never>?

    /** 球馆 / 建筑 / 赛事图层的一次视口（Android `VenueViewport`）。 */
    struct VenueViewport: Hashable {
        var lat: Double
        var lng: Double
        var radiusM: Int
        var summary = false
        var filters = VenueNearbyFilters()
        var refresh = 0
    }

    /* ------------------------------ 派生（Android ExploreUiState 的 get） ------------------------------ */

    /** 地图筛选角标：搜索词加活动、球馆筛选（地图不用距离和排序）。 */
    var filterCount: Int {
        (search.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1) + eventFilters.mapActiveCount + venueFilters.mapActiveCount
    }

    var hasMyLocation: Bool { myLocationLat != nil && myLocationLng != nil }
    var venueRadiusM: Int { layers.venueRadiusM(radiusM) }
    var showEventCards: Bool { map.showEventCards == true }
    var showVenueCards: Bool { map.showVenueCards == true }

    /** 按运动过滤后的球馆（针和面板列表共用）。 */
    var visibleVenuePins: [NearbyVenuePin] {
        guard let sport else { return venuePins }
        return venuePins.filter { pin in pin.sports.contains { $0.loopSport == sport } }
    }

    /** 没有 Loop 球馆的建筑：有球馆的建筑只显示成那个球馆。每次读都重算，后到的球馆也会盖过建筑。 */
    var visibleBuildingPins: [BuildingItem] {
        let venueBuildingIds = Set(venuePins.map(\.building.id))
        return buildingPins.filter { !venueBuildingIds.contains($0.id) }
    }

    /** 选了一个运动时，点到的活动或球馆显示自己的预览卡，不进共用面板。 */
    var previewEvent: ExplorePin? { sport == nil ? nil : pins.first { $0.id == selectedPinId } }
    var previewVenue: NearbyVenuePin? { sport == nil ? nil : venuePins.first { $0.id == selectedVenueId } }

    var pageCount: Int { total > 0 ? (total + pageSize - 1) / pageSize : 0 }
    var canGoPrev: Bool { pageIndex > 0 }
    var canGoNext: Bool { pageCount > 0 && pageIndex < pageCount - 1 }
    var showPager: Bool { pageCount > 1 }
    var hasSelection: Bool { selectedPinId != nil || selectedVenueId != nil || selectedBuildingId != nil || selectedTournamentId != nil }

    private var originLat: Double { myLocationLat ?? centerLat }
    private var originLng: Double { myLocationLng ?? centerLng }

    /** 从我（没有定位时是视野中心）到某点的米数；没有坐标时 nil。 */
    func distanceToM(_ lat: Double?, _ lng: Double?) -> Double? {
        guard let lat, let lng else { return nil }
        return haversineM(originLat, originLng, lat, lng)
    }

    /** 面板里「附近」列表的中心：点中的活动、球馆、建筑或赛事；什么都没点时是我（或视野中心）。 */
    private var sheetAnchor: (Double, Double) {
        if let pin = pins.first(where: { $0.id == selectedPinId }), let lat = pin.locationLat, let lng = pin.locationLng { return (lat, lng) }
        let venue = venuePins.first { $0.id == selectedVenueId } ?? venuePins.first { selectedBuildingId != nil && $0.building.id == selectedBuildingId }
        if let venue, let lat = venue.pinLat, let lng = venue.pinLng { return (lat, lng) }
        if let building = buildingPins.first(where: { $0.id == selectedBuildingId }) { return (building.locationLat, building.locationLng) }
        if let tournament = tournamentPins.first(where: { $0.id == selectedTournamentId }) { return (tournament.lat, tournament.lng) }
        return (originLat, originLng)
    }

    /** 从 [sheetAnchor] 到某点的米数：面板列表的顺序和距离。 */
    func distanceFromAnchorM(_ lat: Double?, _ lng: Double?) -> Double? {
        guard let lat, let lng else { return nil }
        let (anchorLat, anchorLng) = sheetAnchor
        return haversineM(anchorLat, anchorLng, lat, lng)
    }

    /** 视野里的活动，离选中的地点由近到远；选中的那条已经在卡片里，不重复。 */
    var sortedEvents: [ExplorePin] {
        pins.filter { $0.id != selectedPinId }
            .sorted { (distanceFromAnchorM($0.locationLat, $0.locationLng) ?? .greatestFiniteMagnitude) < (distanceFromAnchorM($1.locationLat, $1.locationLng) ?? .greatestFiniteMagnitude) }
    }

    /** 视野里的球馆，同样按选中的地点排；选中的球馆（或选中建筑上的球馆）不重复。 */
    var sortedVenues: [NearbyVenuePin] {
        visibleVenuePins.filter { $0.id != selectedVenueId && (selectedBuildingId == nil || $0.building.id != selectedBuildingId) }
            .sorted { (distanceFromAnchorM($0.pinLat, $0.pinLng) ?? .greatestFiniteMagnitude) < (distanceFromAnchorM($1.pinLat, $1.pinLng) ?? .greatestFiniteMagnitude) }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    var avatarURL: URL? { imageURL(avatarImageId) }

    /* ------------------------------ 订阅 ------------------------------ */

    init() {
        // 直接用保存的设备位置开场，不等 GPS。
        if let point = deviceLocation.location.value?.point {
            myLocationLat = point.latitude
            myLocationLng = point.longitude
            centerLat = point.latitude
            centerLng = point.longitude
        }
    }

    func observe() async {
        await concurrently([
            {
                for await preference in self.preferenceService.preference.values() {
                    self.map = preference.map
                    self.pageSize = preference.event.nearbyPageSize.clamped(to: EventPreferenceLimits.pageSize)
                    self.eventRadiusRange = preference.event.nearbyRadiusMinM ... max(preference.event.nearbyRadiusMinM, preference.event.nearbyRadiusMaxM)
                    self.sync()
                }
            },
            {
                for await info in self.profileStore.current.values() {
                    self.isPulser = info?.isPulser == true
                    self.displayName = info?.displayName
                    self.avatarImageId = info?.avatarImageId
                }
            },
            {
                for await session in self.sessionStore.state.values() {
                    self.session = session
                    self.sync()
                }
            },
            {
                for await filters in self.eventFilterStore.filters.values() {
                    guard filters != self.eventFilters else { continue }
                    self.eventFilters = filters
                    self.pageIndex = 0
                    self.sync()
                }
            },
            {
                for await filters in self.venueFilterStore.filters.values() {
                    self.venueFilters = filters
                    self.sync()
                }
            },
            {
                for await layers in self.layerStore.settings.values() {
                    self.applyLayers(layers)
                }
            },
            {
                // 人像针是设备本身，不是选来搜索的点。
                for await device in self.deviceLocation.location.values() {
                    guard let point = device?.point else { continue }
                    let firstFix = self.myLocationLat == nil || self.myLocationLng == nil
                    self.myLocationLat = point.latitude
                    self.myLocationLng = point.longitude
                    // 只有第一次定位自动飞过去；之后拖图、选点不抢相机。
                    if firstFix { self.flyTo(point.latitude, point.longitude) }
                }
            },
            {
                for await focus in self.focusStore.focus.values() {
                    guard focus != nil, let consumed = self.focusStore.consume() else { continue }
                    if consumed.venueId != nil { self.layerStore.update { $0.showVenueLayer = true } }
                    self.selectedPinId = consumed.eventId
                    self.selectedVenueId = consumed.venueId
                    self.centerLat = consumed.latitude
                    self.centerLng = consumed.longitude
                    self.camera = MapCameraRequest(
                        id: (self.camera?.id ?? 0) + 1,
                        latitude: consumed.latitude,
                        longitude: consumed.longitude,
                        zoom: self.cameraZoom.clamped(to: 14 ... 17)
                    )
                    self.sync()
                }
            },
        ])
    }

    private func applyLayers(_ next: ExploreLayerSettings) {
        layers = next
        if !next.showEventLayer {
            pins = []
            total = 0
            selectedPinId = nil
        }
        if !next.showVenueLayer {
            selectedVenueId = nil
            selectedBuildingId = nil
            buildingPins = []
        }
        if !next.showTournamentLayer {
            tournamentPins = []
            selectedTournamentId = nil
        }
        sync()
    }

    /**
     * 每次状态变了都调一次：算出各图层和预览当前该用的 key，变了就取消旧请求、换新的（Android 各 `launchIn`
     * 里的 `distinctUntilChanged` + `flatMapLatest` / `collectLatest`）。
     */
    private func sync() {
        syncEvents()
        syncVenues()
        syncBuildings()
        syncTournaments()
        syncPreviews()
    }

    private func syncEvents() {
        let available = sport?.available ?? true
        guard isMapReady, layers.showEventLayer, !session.currentProfileId.isEmpty else {
            eventsKey = nil
            eventsTask?.cancel()
            return
        }
        guard available else {
            eventsKey = nil
            eventsTask?.cancel()
            pins = []
            total = 0
            isLoading = false
            return
        }
        let (startsAtFrom, startsAtTo) = eventFilters.startsAtRange()
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = NearbyPinsKey(
            accountId: session.currentAccountId,
            profileId: session.currentProfileId,
            longitude: centerLng,
            latitude: centerLat,
            radiusM: radiusM,
            includeEnded: eventFilters.includeEnded,
            search: trimmed.isEmpty ? nil : trimmed,
            startsAtFrom: startsAtFrom,
            startsAtTo: startsAtTo,
            maxPrice: eventFilters.priceCap.max,
            offset: pageIndex * pageSize,
            limit: pageSize,
            eventTypes: sport.map { [$0.eventType] } ?? [],
            openSpotsOnly: eventFilters.openSpotsOnly
        )
        guard key != eventsKey else { return }
        eventsKey = key
        eventsTask?.cancel()
        let stream = exploreService.query.nearby.stream(key)
        eventsTask = Task { [weak self] in
            for await response in stream {
                guard let self, !Task.isCancelled else { return }
                switch response {
                case let .data(page):
                    self.pins = page.items
                    self.total = page.total
                    self.isLoading = false
                    self.error = nil
                case .loading:
                    self.isLoading = self.pins.isEmpty
                    self.error = nil
                case let .error(error):
                    self.isLoading = false
                    self.error = error.kind
                    self.pins = []
                }
                self.syncPreviews()
            }
        }
    }

    private func syncVenues() {
        guard isMapReady, layers.showVenueLayer else {
            venuesKey = nil
            venuesTask?.cancel()
            return
        }
        let key = VenueViewport(lat: centerLat, lng: centerLng, radiusM: venueRadiusM, summary: !showVenueCards, filters: venueFilters)
        guard key != venuesKey else { return }
        venuesKey = key
        venuesTask?.cancel()
        if lastVenueShape.map({ $0.summary != key.summary || $0.filters != key.filters }) ?? true { venuePins = [] }
        lastVenueShape = (key.summary, key.filters)
        let service = venueService
        venuesTask = Task { [weak self] in
            var offset = 0
            while !Task.isCancelled {
                // 地图图层尽力而为：某页失败就保持现状。
                guard let page = try? await service.getNearby(NearbyVenuesKey(
                    longitude: key.lng,
                    latitude: key.lat,
                    radiusM: key.radiusM,
                    openNow: key.filters.openNow,
                    acceptsMembership: key.filters.acceptsMembership,
                    acceptsPlatform: key.filters.acceptsPlatform,
                    maxHourlyPrice: key.filters.hourlyCap.max,
                    amenities: key.filters.amenityIcons,
                    offset: offset,
                    limit: Self.venuePageSize,
                    summary: key.summary
                )), let self, !Task.isCancelled else { return }
                self.venuePins = mergeById(self.venuePins, page.items, id: \.id)
                self.syncPreviews()
                if page.items.count < Self.venuePageSize { break }
                offset += Self.venuePageSize
            }
        }
    }

    private func syncBuildings() {
        guard isMapReady, layers.showVenueLayer else {
            buildingsKey = nil
            buildingsTask?.cancel()
            buildingPins = []
            return
        }
        let key = VenueViewport(lat: centerLat, lng: centerLng, radiusM: venueRadiusM, refresh: buildingsRefresh)
        guard key != buildingsKey else { return }
        buildingsKey = key
        buildingsTask?.cancel()
        let service = buildingService
        buildingsTask = Task { [weak self] in
            guard let page = try? await service.listNearbyBuildings(
                lat: key.lat,
                lng: key.lng,
                radiusM: key.radiusM,
                buildingTypes: BuildingType.loop.map(\.rawValue),
                limit: Self.buildingPageSize
            ), let self, !Task.isCancelled else { return }
            // 原样按 id 合并，已画的建筑留着；有球馆的建筑在显示时去掉（[visibleBuildingPins]）。
            self.buildingPins = mergeById(self.buildingPins, page.items, id: \.id)
        }
    }

    private func syncTournaments() {
        guard isMapReady, layers.showTournamentLayer else {
            tournamentsKey = nil
            tournamentsTask?.cancel()
            return
        }
        let key = VenueViewport(lat: centerLat, lng: centerLng, radiusM: venueRadiusM)
        guard key != tournamentsKey else { return }
        tournamentsKey = key
        tournamentsTask?.cancel()
        let service = tournamentService
        tournamentsTask = Task { [weak self] in
            guard let pins = try? await service.nearby(latitude: key.lat, longitude: key.lng, radiusM: Double(key.radiusM)),
                  let self, !Task.isCancelled else { return }
            self.tournamentPins = mergeById(self.tournamentPins, pins, id: \.id)
        }
    }

    /** 选中的活动或球馆变了就重拉预览卡要的详情。 */
    private func syncPreviews() {
        let selectedEvent = pins.first { $0.id == selectedPinId }
        if selectedEvent?.id != eventPreviewKey {
            eventPreviewKey = selectedEvent?.id
            eventPreviewTask?.cancel()
            eventPreview = Loadable(isLoading: selectedEvent != nil)
            if let selectedEvent, let service = sportServices[LoopSport.fromEventType(selectedEvent.eventType)] {
                let stream = service.detail(eventId: selectedEvent.id).mapResponses { detail in
                    ExploreEventPreview(
                        imageIds: detail.imageIds,
                        description: detail.event.description,
                        capacity: detail.event.capacity,
                        participating: detail.event.participatingCount
                    )
                }
                eventPreviewTask = Task { [weak self] in
                    for await response in stream {
                        guard let self, !Task.isCancelled else { return }
                        self.eventPreview = self.eventPreview.reduce(response)
                    }
                }
            }
        }
        if selectedVenueId != venuePreviewKey {
            venuePreviewKey = selectedVenueId
            venuePreviewTask?.cancel()
            venuePreviewImageIds = []
            if let venueId = selectedVenueId {
                let stream = venueService.streamVenue(venueId)
                venuePreviewTask = Task { [weak self] in
                    for await response in stream {
                        guard let self, !Task.isCancelled else { return }
                        if case let .data(venue) = response {
                            self.venuePreviewImageIds = venue.images.sorted { $0.sortOrder < $1.sortOrder }.map(\.imageId)
                        }
                    }
                }
            }
        }
    }

    /* ------------------------------ 相机 ------------------------------ */

    func onMapReady() {
        guard !isMapReady else { return }
        isMapReady = true
        sync()
    }

    func onCameraIdle(_ idle: MapCameraIdle) {
        cameraZoom = idle.zoom.clamped(to: 3 ... 20)
        scheduleViewportReload(lat: idle.latitude, lng: idle.longitude, radiusM: idle.radiusM.clamped(to: eventRadiusRange), debounce: Self.viewportDebounce)
    }

    private func scheduleViewportReload(lat: Double, lng: Double, radiusM: Int, debounce: Duration?) {
        viewportTask?.cancel()
        viewportTask = Task { [weak self] in
            if let debounce { try? await Task.sleep(for: debounce) }
            guard let self, !Task.isCancelled else { return }
            self.centerLat = lat
            self.centerLng = lng
            self.radiusM = radiusM
            self.pageIndex = 0
            self.sync()
        }
    }

    private func flyTo(_ lat: Double, _ lng: Double) {
        centerLat = lat
        centerLng = lng
        camera = MapCameraRequest(id: (camera?.id ?? 0) + 1, latitude: lat, longitude: lng, zoom: cameraZoom.clamped(to: 11 ... 16))
        sync()
    }

    /** 选中的针在屏幕外时把相机移过去（缩放不变）；相机停下后再按新中心重拉附近。 */
    private func panTo(_ lat: Double?, _ lng: Double?) {
        guard let lat, let lng else { return }
        camera = MapCameraRequest(id: (camera?.id ?? 0) + 1, latitude: lat, longitude: lng, zoom: nil)
    }

    /** 回到我的位置：先飞到保存的位置，再重新定位、飞到新位置；没有位置就停在原地。 */
    func recenterToMyLocation() {
        flyTo(myLocationLat ?? centerLat, myLocationLng ?? centerLng)
        Task {
            if let fix = await bootstrap.refresh() { flyTo(fix.latitude, fix.longitude) }
        }
    }

    /* ------------------------------ 选择 ------------------------------ */

    func setSportRowVisible(_ visible: Bool) {
        sportRowVisible = visible
    }

    /** nil = 全部。 */
    func selectSport(_ next: LoopSport?) {
        if let next, !next.available { return }
        sport = next
        pageIndex = 0
        sync()
    }

    func updateEventFilters(_ filters: EventNearbyFilters) {
        eventFilterStore.set(filters)
    }

    func updateVenueFilters(_ filters: VenueNearbyFilters) {
        venueFilterStore.set(filters)
    }

    /** 清掉搜索词，两套已保存的筛选回到默认值。 */
    func resetFilters() {
        search = ""
        eventFilterStore.reset()
        venueFilterStore.reset()
    }

    func selectPin(_ id: String?) {
        select(event: id, venue: id == nil ? selectedVenueId : nil, building: id == nil ? selectedBuildingId : nil, tournament: id == nil ? selectedTournamentId : nil)
        if let pin = pins.first(where: { $0.id == id }) { panTo(pin.locationLat, pin.locationLng) }
    }

    func selectVenue(_ id: String?) {
        select(event: id == nil ? selectedPinId : nil, venue: id, building: id == nil ? selectedBuildingId : nil, tournament: id == nil ? selectedTournamentId : nil)
        if let pin = venuePins.first(where: { $0.id == id }) { panTo(pin.pinLat, pin.pinLng) }
    }

    func selectBuilding(_ id: String?) {
        select(event: id == nil ? selectedPinId : nil, venue: id == nil ? selectedVenueId : nil, building: id, tournament: id == nil ? selectedTournamentId : nil)
        if let building = buildingPins.first(where: { $0.id == id }) { panTo(building.locationLat, building.locationLng) }
    }

    func selectTournament(_ id: String?) {
        select(event: id == nil ? selectedPinId : nil, venue: id == nil ? selectedVenueId : nil, building: id == nil ? selectedBuildingId : nil, tournament: id)
        if let pin = tournamentPins.first(where: { $0.id == id }) { panTo(pin.lat, pin.lng) }
    }

    func select(_ item: ExploreMapItem) {
        switch item {
        case let .event(pin): selectPin(pin.id)
        case let .venue(pin): selectVenue(pin.id)
        case let .building(building): selectBuilding(building.id)
        case let .tournament(pin): selectTournament(pin.id)
        }
    }

    private func select(event: String?, venue: String?, building: String?, tournament: String?) {
        selectedPinId = event
        selectedVenueId = venue
        selectedBuildingId = building
        selectedTournamentId = tournament
        syncPreviews()
    }

    /** 手拖地图：卡片都收起。 */
    func clearSelection() {
        select(event: nil, venue: nil, building: nil, tournament: nil)
    }

    func goPrevPage() {
        guard canGoPrev else { return }
        pageIndex -= 1
        selectedPinId = nil
        sync()
    }

    func goNextPage() {
        guard canGoNext else { return }
        pageIndex += 1
        selectedPinId = nil
        sync()
    }

    func retryNearby() {
        exploreService.invalidate()
        venueService.invalidate()
        buildingsRefresh += 1
        sync()
    }

    /* ------------------------------ 图层与地图设置 ------------------------------ */

    func setShowEventLayer(_ show: Bool) {
        layerStore.update { $0.showEventLayer = show }
    }

    func setShowVenueLayer(_ show: Bool) {
        layerStore.update { $0.showVenueLayer = show }
    }

    func setShowTournamentLayer(_ show: Bool) {
        layerStore.update { $0.showTournamentLayer = show }
    }

    func setVenueRadiusMode(_ mode: VenueRadiusMode) {
        layerStore.update { $0.venueRadiusMode = mode }
    }

    func setVenueRadiusMultiplier(_ multiplier: Double) {
        layerStore.update { $0.venueRadiusMultiplier = multiplier }
    }

    func setVenueRadiusFixedKm(_ km: Int) {
        layerStore.update { $0.venueRadiusFixedKm = km }
    }

    func toggleMapFlat() {
        let next = !map.mapflat
        preferenceService.update { $0.map.mapflat = next }
    }

    func toggleMapNearbyRange() {
        let next = !map.mapNearbyRange
        preferenceService.update { $0.map.mapNearbyRange = next }
    }

    /** 活动卡片默认不显示；打开后地图上一直显示，并同步到账号。 */
    func toggleShowEventCards() {
        let next = !showEventCards
        Task { await PreferenceSync.save { $0.map.showEventCards = next } }
    }

    /** 球馆卡片默认不显示；打开后地图上一直显示，并同步到账号。 */
    func toggleShowVenueCards() {
        let next = !showVenueCards
        Task { await PreferenceSync.save { $0.map.showVenueCards = next } }
    }

    /* ------------------------------ 地址搜索（Android ExploreAddressSearch） ------------------------------ */

    /** 只改字不搜；清空时收起结果。 */
    func onAddressQueryChange() {
        if addressQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            addressHits = []
            addressSearchSucceeded = false
            addressSearchError = nil
        }
    }

    func clearAddressSearch() {
        addressTask?.cancel()
        addressQuery = ""
        addressHits = []
        isAddressSearching = false
        addressSearchSucceeded = false
        addressSearchError = nil
    }

    /** 点「搜索」才请求，以我的位置（否则视野中心）为偏好。 */
    func submitAddressSearch() {
        let query = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        addressTask?.cancel()
        guard !query.isEmpty else {
            clearAddressSearch()
            return
        }
        let lat = myLocationLat ?? centerLat
        let lng = myLocationLng ?? centerLng
        isAddressSearching = true
        addressSearchError = nil
        addressSearchSucceeded = false
        let service = locationService
        addressTask = Task { [weak self] in
            do {
                let output = try await service.searchLocation(query: query, lat: lat, lng: lng)
                guard let self, !Task.isCancelled else { return }
                self.addressHits = (output.resultItems ?? []).compactMap { item in
                    guard let position = item.resolvedPositionLngLat else { return nil }
                    let label = item.resolvedLabel.isEmpty ? query : item.resolvedLabel
                    let title = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? label
                    return LocationSearchHit(title: title, label: label, latitude: position.latitude, longitude: position.longitude)
                }
                self.isAddressSearching = false
                self.addressSearchSucceeded = true
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.addressHits = []
                self.isAddressSearching = false
                self.addressSearchError = UiError(error).text(fallback: String(localized: "explore_address_search_failed"))
            }
        }
    }

    /** 相机飞到结果，并以那里刷新附近；人像针留在设备位置。 */
    func selectAddressHit(_ hit: LocationSearchHit) {
        clearAddressSearch()
        flyTo(hit.latitude, hit.longitude)
        scheduleViewportReload(lat: hit.latitude, lng: hit.longitude, radiusM: radiusM, debounce: nil)
    }

    /* ------------------------------ 跳转 ------------------------------ */

    /** 订场：地图上选的运动这家有就用它，否则用它的第一个运动。 */
    func bookRoute(_ pin: NearbyVenuePin) -> LoopRoute? {
        guard let venueSport = pin.sports.first(where: { $0.loopSport == sport }) ?? pin.sports.first else { return nil }
        return .venueBook(venueId: pin.id, sport: venueSport)
    }

    /** 打开详情前先预拉，详情页一进来就有数据。 */
    func prefetchEventDetail(_ pin: ExplorePin) {
        sportServices[LoopSport.fromEventType(pin.eventType)]?.prefetchDetail(eventId: pin.id)
    }
}

/** 已画的针留着，拉到的加进来或刷新，挪地图时图层不会一下变空。 */
private func mergeById<T>(_ current: [T], _ fetched: [T], id: (T) -> String) -> [T] {
    var order: [String] = []
    var byId: [String: T] = [:]
    for item in current + fetched {
        let key = id(item)
        if byId[key] == nil { order.append(key) }
        byId[key] = item
    }
    return order.compactMap { byId[$0] }
}

/** 屏幕上挨得太近的针合成一个聚合针；[id] 用第一个成员的 key，平移时不变（Android `ExploreMapCluster`）。 */
struct ExploreMapCluster: Identifiable {
    let id: String
    let center: CGPoint
    let items: [ExploreMapItem]
}

/**
 * 把投影后的屏幕点在 [radius] 以内的针归到同一组的第一个针下，其余单独显示（Android `clusterByScreen`）。
 * 针是叠在地图上的 SwiftUI 视图，所以按屏幕点算（MapLibre 自己的聚合只管 GeoJSON 图层）。
 */
func clusterByScreen(_ points: [(ExploreMapItem, CGPoint)], radius: CGFloat) -> (singles: [ExploreMapItem], clusters: [ExploreMapCluster]) {
    var taken = [Bool](repeating: false, count: points.count)
    var singles: [ExploreMapItem] = []
    var clusters: [ExploreMapCluster] = []
    let radiusSq = radius * radius
    for i in points.indices where !taken[i] {
        taken[i] = true
        let (seed, seedAt) = points[i]
        var members = [(seed, seedAt)]
        for j in points.indices where j > i && !taken[j] {
            let (item, at) = points[j]
            let dx = at.x - seedAt.x
            let dy = at.y - seedAt.y
            if dx * dx + dy * dy <= radiusSq {
                taken[j] = true
                members.append((item, at))
            }
        }
        if members.count == 1 {
            singles.append(seed)
        } else {
            let center = CGPoint(
                x: members.map(\.1.x).reduce(0, +) / CGFloat(members.count),
                y: members.map(\.1.y).reduce(0, +) / CGFloat(members.count)
            )
            clusters.append(ExploreMapCluster(id: seed.id, center: center, items: members.map(\.0)))
        }
    }
    return (singles, clusters)
}
