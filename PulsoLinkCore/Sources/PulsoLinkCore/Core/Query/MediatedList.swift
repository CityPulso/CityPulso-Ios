import Foundation
import Observation

/** 页面只读的分页列表：[PagedList]（只走网络）和 [MediatedList]（本地库为准）都能用同一套行渲染。 */
@MainActor
public protocol PagedRows<Item>: AnyObject {
    associatedtype Item: Sendable
    var items: [Item] { get }
    var isLoading: Bool { get }
    var isLoadingMore: Bool { get }
    var error: UiError? { get }
    /** 有行，但刷新失败（页面顶部提示）。 */
    var staleError: UiError? { get }
    var appendError: UiError? { get }
    var endReached: Bool { get }
    var isEmpty: Bool { get }
    func observe() async
    func refresh() async
    func loadMore()
}

extension PagedList: PagedRows {
    /** 只走网络的列表失败时没有旧行可留。 */
    public var staleError: UiError? { nil }
}

/**
 * 离线优先的分页列表（Android Paging 3 `RemoteMediator` + Room `PagingSource`）：显示的行一直来自本地库，
 * 网络只负责一页一页填进去。刷新 = 重拉第一页替换本地；翻页 = 从上次拉到的位置接着拉。
 * 网络失败时本地已有的行照样显示（[error] 只在本地也没有行时用来显示错误页）。
 */
@MainActor
@Observable
public final class MediatedList<Item: Sendable>: PagedRows {
    public private(set) var items: [Item] = []
    /** 本地还没读出来，或本地没有行且第一页还没回来。 */
    public private(set) var isLoading = true
    public private(set) var isLoadingMore = false
    public private(set) var error: UiError?
    /** 刷新失败但还有本地行（页面顶部提示，行不动）。 */
    public private(set) var staleError: UiError?
    public private(set) var appendError: UiError?
    public private(set) var endReached = false

    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let reader: @Sendable () -> AsyncStream<[Item]?>
    @ObservationIgnored private let load: @Sendable (_ offset: Int, _ limit: Int) async throws -> Int?
    @ObservationIgnored private let invalidates: @Sendable () -> AsyncStream<Void>
    @ObservationIgnored private var next: Int?
    @ObservationIgnored private var fetchedOnce = false
    /** 第一页还没回来时有人要下一页（本地行先到、最后一行已经出现）：第一页回来后接着拉。 */
    @ObservationIgnored private var wantsMore = false
    @ObservationIgnored private var generation = 0

    /**
     * [reader]：本地库里这份列表的行（还没拉过为 nil）。
     * [load]：拉一页并写进本地库（offset 0 时整份替换），返回下一页的 offset（nil = 到底）。
     */
    public init(
        pageSize: Int = offsetPageSize,
        invalidates: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        reader: @escaping @Sendable () -> AsyncStream<[Item]?>,
        load: @escaping @Sendable (_ offset: Int, _ limit: Int) async throws -> Int?
    ) {
        self.pageSize = pageSize
        self.invalidates = invalidates
        self.reader = reader
        self.load = load
    }

    public var isEmpty: Bool { !isLoading && error == nil && items.isEmpty }

    /** 订阅本地行、拉第一页，之后每次失效都重拉第一页；页面消失时随 `.task` 取消。 */
    public func observe() async {
        let rows = reader()
        let local = Task { @MainActor in
            for await value in rows {
                items = value ?? []
                if value != nil, !items.isEmpty { isLoading = false }
            }
        }
        await withTaskCancellationHandler {
            await refresh()
            for await _ in invalidates() {
                await refresh()
            }
            // 没有更多失效时也一直读本地行，直到页面消失（调用方被取消）。
            await local.value
        } onCancel: {
            local.cancel()
        }
    }

    public func refresh() async {
        generation += 1
        let current = generation
        error = nil
        staleError = nil
        appendError = nil
        do {
            let following = try await load(0, pageSize)
            guard current == generation else { return }
            accept(following)
            if wantsMore {
                wantsMore = false
                loadMore()
            }
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            if items.isEmpty { self.error = UiError(error) } else { staleError = UiError(error) }
        }
        isLoading = false
    }

    public func loadMore() {
        guard fetchedOnce else {
            wantsMore = true
            return
        }
        guard !isLoadingMore, !endReached, let next else { return }
        isLoadingMore = true
        appendError = nil
        let current = generation
        Task {
            defer { if current == generation { isLoadingMore = false } }
            do {
                let following = try await load(next, pageSize)
                guard current == generation else { return }
                accept(following)
            } catch {
                guard current == generation else { return }
                appendError = UiError(error)
            }
        }
    }

    private func accept(_ following: Int?) {
        fetchedOnce = true
        next = following
        endReached = following == nil
    }
}

/** 一页写完以后下一页从哪里开始（到底时 nil）。 */
public func nextOffset(after offset: Int, count: Int, total: Int) -> Int? {
    let reached = offset + count
    return count > 0 && reached < total ? reached : nil
}
