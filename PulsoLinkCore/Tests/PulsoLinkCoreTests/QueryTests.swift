import Foundation
import Testing
@testable import PulsoLinkCore

/** 计数的假 fetcher：每次调用返回递增的版本号。 */
private actor Counter {
    private(set) var calls = 0
    func next() -> Int {
        calls += 1
        return calls
    }
}

private struct Boom: Error {}

/** 收集 stream 的前 [count] 个结果。 */
private func take<T: Sendable>(_ count: Int, from stream: AsyncStream<QueryResponse<T>>) async -> [QueryResponse<T>] {
    var out: [QueryResponse<T>] = []
    for await response in stream {
        out.append(response)
        if out.count == count { break }
    }
    return out
}

private func value<T>(_ response: QueryResponse<T>) -> T? {
    if case let .data(value) = response { value } else { nil }
}

struct MemoryQueryTests {
    @Test func getCachesWithinTTL() async throws {
        let counter = Counter()
        let query = MemoryQuery<String, Int> { _ in await counter.next() }
        #expect(try await query.get("a") == 1)
        #expect(try await query.get("a") == 1)
        #expect(try await query.get("b") == 2)
        #expect(await counter.calls == 2)
    }

    @Test func expiredEntryRefetches() async throws {
        let counter = Counter()
        let query = MemoryQuery<String, Int>(ttl: .zero) { _ in await counter.next() }
        #expect(try await query.get("a") == 1)
        #expect(try await query.get("a") == 2)
    }

    @Test func freshAlwaysFetchesAndConcurrentCallsShareOneRequest() async throws {
        let counter = Counter()
        let query = MemoryQuery<String, Int> { _ in
            try await Task.sleep(for: .milliseconds(50))
            return await counter.next()
        }
        async let first = query.fresh("a")
        async let second = query.fresh("a")
        let results = try await [first, second]
        #expect(results == [1, 1])
        #expect(try await query.fresh("a") == 2)
    }

    @Test func streamEmitsLoadingThenDataThenRefetchesOnInvalidate() async throws {
        let counter = Counter()
        let bus = EventBroadcast<Int>()
        let query = MemoryQuery<String, Int>(invalidates: { bus.signals { $0 == 1 } }) { _ in await counter.next() }
        let stream = query.stream("a")
        let collector = Task { await take(4, from: stream) }
        // 等第一轮拉完再发失效；不匹配的事件不触发重拉。
        while await counter.calls < 1 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(20))
        bus.emit(2)
        bus.emit(1)
        let responses = await collector.value
        guard case .loading = responses[0] else {
            Issue.record("expected loading first, got \(responses[0])")
            return
        }
        #expect(value(responses[1]) == 1)
        #expect(value(responses[3]) == 2)
        #expect(await counter.calls == 2)
    }

    @Test func streamShowsCacheFirstAndKeepsItOnError() async throws {
        let failing = Counter()
        let query = MemoryQuery<String, Int> { _ in
            if await failing.next() > 1 { throw Boom() }
            return 7
        }
        _ = try await query.get("a")
        let responses = await take(2, from: query.stream("a"))
        #expect(value(responses[0]) == 7)
        guard case .error = responses[1] else {
            Issue.record("expected error, got \(responses[1])")
            return
        }
        let state = Loadable<Int>().reduce(responses[0]).reduce(responses[1])
        #expect(state.data == 7)
        #expect(state.error != nil)
        #expect(!state.isLoading)
    }

    @Test func setPushesToActiveStreams() async throws {
        let query = MemoryQuery<String, Int> { _ in 1 }
        var iterator = query.stream("a", refresh: false).makeAsyncIterator()
        var seen: [Int] = []
        // 先等到网络那一份，再写，避免 set 和首次拉取赛跑。
        while seen.isEmpty, let response = await iterator.next() {
            if let value = value(response) { seen.append(value) }
        }
        await query.set("a", 9)
        while seen.count < 2, let response = await iterator.next() {
            if let value = value(response) { seen.append(value) }
        }
        #expect(seen == [1, 9])
    }

    @Test func updateAllRewritesCacheAndPushes() async throws {
        let query = MemoryQuery<String, Int> { _ in 1 }
        var iterator = query.stream("a", refresh: false).makeAsyncIterator()
        var seen: [Int] = []
        // 先等到网络那一份写进缓存，再改写；只睡一会儿的话，机器忙时 updateAll 会落空。
        while seen.isEmpty, let response = await iterator.next() {
            if let value = value(response) { seen.append(value) }
        }
        await query.updateAll { $0 + 10 }
        while seen.count < 2, let response = await iterator.next() {
            if let value = value(response) { seen.append(value) }
        }
        #expect(seen == [1, 11])
        #expect(try await query.get("a") == 11)
    }

    @Test func maxSizeEvictsOldest() async throws {
        let counter = Counter()
        let query = MemoryQuery<String, Int>(maxSize: 2) { _ in await counter.next() }
        _ = try await query.get("a")
        _ = try await query.get("b")
        _ = try await query.get("c")
        #expect(try await query.get("b") == 2)
        #expect(try await query.get("a") == 4)
    }
}

private struct Row: Codable, Sendable, Equatable {
    let id: Int
}

@MainActor
struct PagedListTests {
    @Test func offsetPagesUntilTotal() async throws {
        let pager = PagedList<Row, Int>.offset(pageSize: 2) { offset, limit in
            let ids = Array(offset..<min(offset + limit, 5))
            return ListWithTotal(items: ids.map(Row.init), total: 5)
        }
        await pager.refresh()
        #expect(pager.items.map(\.id) == [0, 1])
        #expect(!pager.endReached)
        pager.loadMore()
        while pager.isLoadingMore { await Task.yield() }
        pager.loadMore()
        while pager.isLoadingMore { await Task.yield() }
        #expect(pager.items.map(\.id) == [0, 1, 2, 3, 4])
        #expect(pager.endReached)
        pager.loadMore()
        #expect(!pager.isLoadingMore)
    }

    @Test func cursorStopsOnEmptyNextCursor() async throws {
        let pager = PagedList<Row, String>.cursor(pageSize: 2) { after, _ in
            after.isEmpty
                ? ListWithNextCursor(items: [Row(id: 1)], nextCursor: "c1")
                : ListWithNextCursor(items: [Row(id: 2)], nextCursor: "")
        }
        await pager.refresh()
        pager.loadMore()
        while pager.isLoadingMore { await Task.yield() }
        #expect(pager.items.map(\.id) == [1, 2])
        #expect(pager.endReached)
    }

    @Test func firstPageErrorThenEmpty() async throws {
        let attempts = Counter()
        let pager = PagedList<Row, Int>.offset { _, _ in
            if await attempts.next() == 1 { throw URLError(.notConnectedToInternet) }
            return ListWithTotal(items: [], total: 0)
        }
        await pager.refresh()
        #expect(pager.error?.kind == .offline)
        #expect(!pager.isEmpty)
        await pager.refresh()
        #expect(pager.error == nil)
        #expect(pager.isEmpty)
    }

    @Test func invalidateReloadsFromTop() async throws {
        let version = Counter()
        let bus = EventBroadcast<Void>()
        let pager = PagedList<Row, Int>.offset(invalidates: { bus.signals { _ in true } }) { _, _ in
            ListWithTotal(items: [Row(id: await version.next())], total: 1)
        }
        let observing = Task { await pager.observe() }
        while pager.items.isEmpty { await Task.yield() }
        bus.emit(())
        while pager.items.first?.id != 2 { await Task.yield() }
        observing.cancel()
        #expect(pager.items.map(\.id) == [2])
    }
}
