import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一页要的东西（除了位置和关键词）：nil 活动类型 = 所有活动类型。 */
struct ActivitySearchFilter: Hashable, Sendable {
    let activityType: NearActivityKind?
    let filters: ActivityNearbyFilters
}

/**
 * 附近活动列表（对应 Android `ActivitySearchViewModel`）：每种活动标签一页，可以左右滑；每页有存着的筛选、关键词和无限滚动。
 * 当前页和左右各 [prefetchPages] 页加载，更远的页等用户靠近再加载。
 */
@MainActor
@Observable
final class ActivitySearchModel {
    /** 标签：nil = 所有活动类型，然后每种活动类型。 */
    static let tabs: [NearActivityKind?] = [nil] + NearActivityKind.allCases
    private static let prefetchPages = 2

    private(set) var page = 0
    private(set) var filters: ActivityNearbyFilters
    private(set) var isPulser = false
    let searches: [NearbySearchController<ActivitySearchFilter, ExplorePin, NearbyPinsPage>]

    @ObservationIgnored @Injected(\.exploreService) private var exploreService
    @ObservationIgnored @Injected(\.activityNearbyFilterStore) private var filterStore
    @ObservationIgnored @Injected(\.exploreFocusStore) private var focusStore
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    var activityType: NearActivityKind? { Self.tabs[page] }

    init() {
        let container = Container.shared
        let explore = container.exploreService()
        let sessionStore = container.authSessionStore()
        let preferences = container.preferenceService()
        filters = container.activityNearbyFilterStore().filters.value
        searches = Self.tabs.map { _ in
            NearbySearchController(
                locationStore: container.nearbyQueryLocationStore(),
                pageSize: { preferences.preference.value.event.nearbyPageSize },
                firstPage: { query in explore.query.nearby.stream(Self.key(query, session: sessionStore.state.value)) },
                nextPage: { query in try await explore.query.nearby.get(Self.key(query, session: sessionStore.state.value)) },
                itemsOf: \.items,
                totalOf: \.total,
                onLoadMoreFailed: { PulsoMessageCenter.shared.error($0, fallback: "shell_search_load_more_failed") }
            )
        }
        applyFilters()
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /** 跟着存着的筛选和当前身份；页面消失时随 `.task` 取消。 */
    func observe() async {
        var operations: [@MainActor () async -> Void] = [
            {
                for await next in self.filterStore.filters.values() {
                    self.filters = next
                    self.applyFilters()
                }
            },
            {
                for await info in self.profileStore.current.values() {
                    self.isPulser = info?.isPulser == true
                }
            },
        ]
        for search in searches {
            operations.append { await search.observeLocation() }
        }
        await concurrently(operations)
    }

    /** 翻到第 [index] 页，左右的页开始加载。 */
    func selectPage(_ index: Int) {
        page = index
        applyFilters()
    }

    func store(_ next: ActivityNearbyFilters) {
        filterStore.set(next)
    }

    /** 关键词对所有页都生效。 */
    func onSearchChange(_ value: String) {
        searches.forEach { $0.onSearchChange(value) }
    }

    /** 第 [index] 页下拉刷新：重拉已加载的页。 */
    func refresh(_ index: Int) async {
        let explore = exploreService
        await searches[index].refresh { explore.invalidate() }
    }

    /** 把这个活动交给地图页定位；没有坐标返回 false。 */
    func focusOnMap(_ pin: ExplorePin) -> Bool {
        guard let lat = pin.locationLat, let lng = pin.locationLng else { return false }
        focusStore.request(ExploreFocus(activityId: pin.id, latitude: lat, longitude: lng))
        return true
    }

    static func activitiesAvailable(_ activityType: NearActivityKind?) -> Bool {
        activityType?.available != false
    }

    private func applyFilters() {
        for (index, search) in searches.enumerated() {
            let activityType = Self.tabs[index]
            let inRange = abs(index - page) <= Self.prefetchPages
            search.setFilter(inRange && Self.activitiesAvailable(activityType) ? ActivitySearchFilter(activityType: activityType, filters: filters) : nil)
        }
    }

    private nonisolated static func key(_ query: NearbyQuery<ActivitySearchFilter>, session: AuthSession) -> NearbyPinsKey {
        let (from, to) = query.filter.filters.startsAtRange()
        return NearbyPinsKey(
            accountId: session.currentAccountId,
            profileId: session.currentProfileId,
            longitude: query.longitude,
            latitude: query.latitude,
            radiusM: query.filter.filters.distance.radiusM,
            includeEnded: query.filter.filters.includeEnded,
            search: query.search,
            startsAtFrom: from,
            startsAtTo: to,
            maxPrice: query.filter.filters.priceCap.max,
            offset: query.offset,
            limit: query.limit,
            activityTypes: query.filter.activityType.map { [$0.activityType] } ?? [],
            openSpotsOnly: query.filter.filters.openSpotsOnly,
            sort: query.filter.filters.sort
        )
    }
}
