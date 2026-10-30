import Observation

/** 每个 offset 列表的页大小，与 WEB `useUnifiedInfiniteQuery`、Android `OFFSET_PAGE_SIZE` 一致。 */
public let offsetPageSize = 20

/** 一页的结果：items + 下一页的位置（nil 表示到底）。 */
public struct Page<Item: Sendable, Cursor: Sendable>: Sendable {
    public let items: [Item]
    public let next: Cursor?

    public init(items: [Item], next: Cursor?) {
        self.items = items
        self.next = next
    }
}

/**
 * 分页列表（对应 Android Paging 3 的 `offsetPager` / `cursorPager`、WEB `useInfiniteQuery`）：
 * 第一页、追加下一页、下拉刷新、失效后从头重拉。用 [offset] / [cursor] 两个工厂建，页面只读状态。
 *
 * 页面用法：`List` 的最后一行 `.onAppear { pager.loadMore() }`，`.refreshable { await pager.refresh() }`，
 * `.task { await pager.observe() }`。
 */
@MainActor
@Observable
public final class PagedList<Item: Sendable, Cursor: Sendable> {
    public private(set) var items: [Item] = []
    /** 第一页还没回来。 */
    public private(set) var isLoading = true
    public private(set) var isLoadingMore = false
    /** 第一页失败（页面显示加载失败 + 重试）。 */
    public private(set) var error: UiError?
    /** 下一页失败（列表底部显示重试，已加载的不动）。 */
    public private(set) var appendError: UiError?
    public private(set) var endReached = false

    @ObservationIgnored private let first: Cursor
    @ObservationIgnored private let fetch: @Sendable (Cursor, Int) async throws -> Page<Item, Cursor>
    @ObservationIgnored private let invalidates: @Sendable () -> AsyncStream<Void>
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var next: Cursor?
    /** 每次从头加载换一代，旧一代回来的页丢掉。 */
    @ObservationIgnored private var generation = 0

    init(
        first: Cursor,
        pageSize: Int,
        invalidates: @escaping @Sendable () -> AsyncStream<Void>,
        fetch: @escaping @Sendable (Cursor, Int) async throws -> Page<Item, Cursor>
    ) {
        self.first = first
        self.pageSize = pageSize
        self.invalidates = invalidates
        self.fetch = fetch
    }

    public var isEmpty: Bool {
        !isLoading && error == nil && items.isEmpty
    }

    /** 加载第一页，之后每次失效都从头重拉；页面消失时随 `.task` 取消。 */
    public func observe() async {
        // 先订阅再拉第一页：拉的过程中来的失效不会丢。
        let pulses = invalidates()
        if items.isEmpty { await refresh() }
        for await _ in pulses {
            await refresh()
        }
    }

    /** 从头加载（下拉刷新、失效、重试第一页）。已有数据在新数据回来前保留。 */
    public func refresh() async {
        generation += 1
        let current = generation
        isLoading = items.isEmpty
        error = nil
        appendError = nil
        do {
            let page = try await fetch(first, pageSize)
            guard current == generation else { return }
            items = page.items
            accept(page)
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            self.error = UiError(error)
        }
        isLoading = false
    }

    /** 追加下一页；正在加载、已到底或第一页没好时什么也不做。 */
    public func loadMore() {
        guard !isLoading, !isLoadingMore, !endReached, error == nil, let next else { return }
        isLoadingMore = true
        appendError = nil
        let current = generation
        Task {
            defer { if current == generation { isLoadingMore = false } }
            do {
                let page = try await fetch(next, pageSize)
                guard current == generation else { return }
                items += page.items
                accept(page)
            } catch {
                guard current == generation else { return }
                appendError = UiError(error)
            }
        }
    }

    /** 本地改一行（点赞、状态变化），不重拉。 */
    public func update(where matches: (Item) -> Bool, _ transform: (inout Item) -> Void) {
        for index in items.indices where matches(items[index]) {
            transform(&items[index])
        }
    }

    public func remove(where matches: (Item) -> Bool) {
        items.removeAll(where: matches)
    }

    /** 同一个分页源，每行换成另一种（Android `PagingData.map`）；[transform] 返回 nil 的行丢掉。 */
    public func mapped<Mapped: Sendable>(_ transform: @escaping @Sendable (Item) -> Mapped?) -> PagedList<Mapped, Cursor> {
        let fetch = fetch
        return PagedList<Mapped, Cursor>(first: first, pageSize: pageSize, invalidates: invalidates) { cursor, limit in
            let page = try await fetch(cursor, limit)
            return Page(items: page.items.compactMap(transform), next: page.next)
        }
    }

    private func accept(_ page: Page<Item, Cursor>) {
        next = page.next
        endReached = page.next == nil
    }
}

extension PagedList where Cursor == Int {
    /** `limit/offset + total` 接口；到底 = 这一页为空或已取到 total。 */
    public static func offset(
        pageSize: Int = offsetPageSize,
        invalidates: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        fetch: @escaping @Sendable (_ offset: Int, _ limit: Int) async throws -> ListWithTotal<Item>
    ) -> PagedList<Item, Int> where Item: Codable {
        PagedList(first: 0, pageSize: pageSize, invalidates: invalidates) { offset, limit in
            let list = try await fetch(offset, limit)
            let reached = offset + list.items.count
            return Page(items: list.items, next: !list.items.isEmpty && reached < list.total ? reached : nil)
        }
    }
}

extension PagedList where Cursor == String {
    /** keyset 接口（`after` + `next_cursor`）；第一页传空游标，到底 = `next_cursor` 为空。 */
    public static func cursor(
        pageSize: Int = offsetPageSize,
        invalidates: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        fetch: @escaping @Sendable (_ after: String, _ limit: Int) async throws -> ListWithNextCursor<Item>
    ) -> PagedList<Item, String> where Item: Codable {
        PagedList(first: "", pageSize: pageSize, invalidates: invalidates) { after, limit in
            let list = try await fetch(after, limit)
            let next = list.nextCursor.flatMap { $0.isEmpty || list.items.isEmpty ? nil : $0 }
            return Page(items: list.items, next: next)
        }
    }
}
