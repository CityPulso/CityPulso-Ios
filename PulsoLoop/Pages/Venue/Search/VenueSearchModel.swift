import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一页要的东西（除了位置和关键词）：nil 运动 = 所有运动。 */
struct VenueSearchFilter: Hashable, Sendable {
    let sport: VenueSport?
    let filters: VenueNearbyFilters
}

extension LoopSport {
    /** 这项运动的球馆入口；还没有球馆入口的运动是 nil。 */
    var venueSport: VenueSport? { VenueSport.allCases.first { $0.loopSport == self } }
}

/**
 * 附近球馆（Android `VenueSearchViewModel`）：每个运动标签一页，可以左右滑；每页有存着的筛选、关键词和无限滚动。
 * 当前页和左右各两页加载，更远的等用户靠近。收藏星只标已经加载出来的行。
 */
@MainActor
@Observable
final class VenueSearchModel {
    /** 标签：nil = 所有运动，然后每种运动。 */
    static let tabs: [LoopSport?] = [nil] + LoopSport.allCases
    private static let prefetchPages = 2

    private(set) var page = 0
    private(set) var filters: VenueNearbyFilters
    /** 收藏的球馆 id；没登录或没读到时 nil（不显示星）。 */
    private(set) var favoriteIds: Set<String>?
    let searches: [NearbySearchController<VenueSearchFilter, NearbyVenuePin, NearbyVenuesPage>]

    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.favoriteService) private var favoriteService
    @ObservationIgnored @Injected(\.venueNearbyFilterStore) private var filterStore
    @ObservationIgnored @Injected(\.exploreFocusStore) private var focusStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var favoritesKey: [String] = []

    var sport: LoopSport? { Self.tabs[page] }

    init() {
        let container = Container.shared
        let venues = container.venueService()
        let preferences = container.preferenceService()
        filters = container.venueNearbyFilterStore().filters.value
        searches = Self.tabs.map { _ in
            NearbySearchController(
                locationStore: container.nearbyQueryLocationStore(),
                pageSize: { preferences.preference.value.event.nearbyPageSize },
                firstPage: { query in venues.streamNearby(Self.key(query)) },
                nextPage: { query in try await venues.getNearby(Self.key(query)) },
                itemsOf: \.items,
                totalOf: \.total,
                onLoadMoreFailed: { PulsoMessageCenter.shared.error($0, fallback: "shell_search_load_more_failed") }
            )
        }
        applyFilters()
    }

    static func venuesAvailable(_ sport: LoopSport?) -> Bool {
        sport == nil || sport?.venueSport != nil
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        var operations: [@MainActor () async -> Void] = [
            {
                for await next in self.filterStore.filters.values() {
                    self.filters = next
                    self.applyFilters()
                }
            },
            {
                // 别处切换了收藏：重新问一次。
                for await _ in self.favoriteService.changes.signals(where: { _ in true }) {
                    self.favoritesKey = []
                    await self.refreshFavorites()
                }
            },
        ]
        for search in searches {
            operations.append { await search.observeLocation() }
        }
        await concurrently(operations)
    }

    /** 已加载的行变了才问一次收藏。 */
    func refreshFavorites() async {
        let ids = Array(Set(searches.flatMap { $0.results.data?.map(\.id) ?? [] })).sorted()
        guard ids != favoritesKey else { return }
        favoritesKey = ids
        if let starred = try? await favoriteService.favoriteVenueIds(ids) { favoriteIds = starred }
    }

    func selectPage(_ index: Int) {
        page = index
        applyFilters()
    }

    func store(_ next: VenueNearbyFilters) {
        filterStore.set(next)
    }

    func onSearchChange(_ value: String) {
        searches.forEach { $0.onSearchChange(value) }
    }

    func refresh(_ index: Int) async {
        let venues = venueService
        await searches[index].refresh { venues.invalidate() }
    }

    /** 先改星、失败再改回来并提示。 */
    func toggleFavorite(_ venueId: String) async {
        guard var current = favoriteIds else { return }
        let favorite = !current.contains(venueId)
        if favorite { current.insert(venueId) } else { current.remove(venueId) }
        favoriteIds = current
        do {
            try await favoriteService.setFavorite(.venue, id: venueId, favorite: favorite)
        } catch {
            if favorite { favoriteIds?.remove(venueId) } else { favoriteIds?.insert(venueId) }
            PulsoMessageCenter.shared.error(error, fallback: "favorites_toggle_failed")
        }
    }

    /** 把这家球馆交给地图页定位；没有坐标返回 false。 */
    func focusOnMap(_ pin: NearbyVenuePin) -> Bool {
        guard let lat = pin.pinLat, let lng = pin.pinLng else { return false }
        focusStore.request(ExploreFocus(eventId: nil, latitude: lat, longitude: lng, venueId: pin.id))
        return true
    }

    private func applyFilters() {
        for (index, search) in searches.enumerated() {
            let sport = Self.tabs[index]
            let inRange = abs(index - page) <= Self.prefetchPages
            search.setFilter(inRange && Self.venuesAvailable(sport) ? VenueSearchFilter(sport: sport?.venueSport, filters: filters) : nil)
        }
    }

    private nonisolated static func key(_ query: NearbyQuery<VenueSearchFilter>) -> NearbyVenuesKey {
        let filters = query.filter.filters
        return NearbyVenuesKey(
            longitude: query.longitude,
            latitude: query.latitude,
            radiusM: filters.distance.radiusM,
            search: query.search,
            sports: query.filter.sport.map { [$0] } ?? [],
            openNow: filters.openNow,
            acceptsMembership: filters.acceptsMembership,
            acceptsPlatform: filters.acceptsPlatform,
            maxHourlyPrice: filters.hourlyCap.max,
            amenities: filters.amenityIcons,
            sort: filters.sort,
            offset: query.offset,
            limit: query.limit
        )
    }
}
