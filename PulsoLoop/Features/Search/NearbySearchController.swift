import Foundation
import PulsoLinkCore
import Observation

/** 一次附近搜索：在哪、什么关键词、什么筛选、哪一段。 */
struct NearbyQuery<Filter: Hashable & Sendable>: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let search: String?
    let filter: Filter
    let offset: Int
    let limit: Int
}

/**
 * 活动搜索和球馆搜索共用的引擎（对应 Android `NearbySearchController`）：位置来自 [NearbyQueryLocationStore]，
 * 关键词防抖，第一页走查询缓存的 stream，后面按 offset 追加。页面之间只差 [filter] 和取数函数。
 * [filter] 为 nil 时空闲（离当前标签太远的页先不加载）。
 */
@MainActor
@Observable
final class NearbySearchController<Filter: Hashable & Sendable, Item: Sendable, Page: Sendable> {
    private static var searchDebounce: Duration { .milliseconds(280) }

    private(set) var location: DeviceLocation?
    /** 用户输入的关键词（请求用防抖后的值）。 */
    private(set) var search = ""
    private(set) var results = Loadable<[Item]>()
    private(set) var total = 0
    private(set) var isLoadingMore = false
    /** 下拉刷新在等重拉的结果（列表保留旧行）。 */
    private(set) var isRefreshing = false

    var hasNextPage: Bool { (results.data?.count ?? 0) < total }

    @ObservationIgnored private var filter: Filter?
    @ObservationIgnored private var debouncedSearch: String?
    @ObservationIgnored private var currentQuery: NearbyQuery<Filter>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private let locationStore: NearbyQueryLocationStore
    @ObservationIgnored private let pageSize: () -> Int
    @ObservationIgnored private let firstPage: (NearbyQuery<Filter>) -> AsyncStream<QueryResponse<Page>>
    @ObservationIgnored private let nextPage: @Sendable (NearbyQuery<Filter>) async throws -> Page
    @ObservationIgnored private let itemsOf: (Page) -> [Item]
    @ObservationIgnored private let totalOf: (Page) -> Int
    @ObservationIgnored private let onLoadMoreFailed: (any Error) -> Void

    init(
        locationStore: NearbyQueryLocationStore,
        pageSize: @escaping () -> Int,
        firstPage: @escaping (NearbyQuery<Filter>) -> AsyncStream<QueryResponse<Page>>,
        nextPage: @escaping @Sendable (NearbyQuery<Filter>) async throws -> Page,
        itemsOf: @escaping (Page) -> [Item],
        totalOf: @escaping (Page) -> Int,
        onLoadMoreFailed: @escaping (any Error) -> Void
    ) {
        self.locationStore = locationStore
        self.pageSize = pageSize
        self.firstPage = firstPage
        self.nextPage = nextPage
        self.itemsOf = itemsOf
        self.totalOf = totalOf
        self.onLoadMoreFailed = onLoadMoreFailed
        location = locationStore.current
    }

    /** 跟着搜索中心变化重查；页面消失时随 `.task` 取消。 */
    func observeLocation() async {
        for await next in locationStore.values() {
            location = next
            reload()
        }
    }

    func setFilter(_ next: Filter?) {
        guard next != filter else { return }
        filter = next
        reload()
    }

    func onSearchChange(_ value: String) {
        search = value
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            debouncedSearch = trimmed.isEmpty ? nil : trimmed
            reload()
        }
    }

    /** 下拉刷新：[invalidate] 让查询缓存重拉；转圈直到结果回来。 */
    func refresh(_ invalidate: () -> Void) async {
        guard currentQuery != nil else { return }
        isRefreshing = true
        invalidate()
        while isRefreshing, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func loadNextPage() {
        guard let query = currentQuery, hasNextPage, !isLoadingMore, !results.isLoading else { return }
        loadMoreTask?.cancel()
        isLoadingMore = true
        let next = NearbyQuery(
            latitude: query.latitude, longitude: query.longitude, search: query.search,
            filter: query.filter, offset: results.data?.count ?? 0, limit: query.limit
        )
        let fetch = nextPage
        loadMoreTask = Task {
            defer { isLoadingMore = false }
            do {
                let page = try await fetch(next)
                guard currentQuery == query else { return }
                results = results.map { $0 + itemsOf(page) }
                total = totalOf(page)
            } catch is CancellationError {
                return
            } catch {
                onLoadMoreFailed(error)
            }
        }
    }

    private func reload() {
        let query: NearbyQuery<Filter>? = if let location, let filter {
            NearbyQuery(
                latitude: location.point.latitude, longitude: location.point.longitude,
                search: debouncedSearch, filter: filter, offset: 0, limit: pageSize()
            )
        } else {
            nil
        }
        guard query != currentQuery || streamTask == nil else { return }
        currentQuery = query
        streamTask?.cancel()
        loadMoreTask?.cancel()
        isLoadingMore = false
        guard let query else {
            streamTask = nil
            results = Loadable(data: [], isLoading: false)
            total = 0
            return
        }
        let stream = firstPage(query)
        streamTask = Task {
            var page = Loadable<Page>()
            for await response in stream {
                page = page.reduce(response)
                results = page.map(itemsOf)
                total = page.data.map(totalOf) ?? 0
                if case .loading = response { continue }
                isRefreshing = false
            }
        }
    }
}
