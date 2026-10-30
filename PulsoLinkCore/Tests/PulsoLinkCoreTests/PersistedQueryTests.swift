import Foundation
import Testing
@testable import PulsoLinkCore

private func friend(_ id: String) -> FriendItem {
    FriendItem(friendshipId: "f-\(id)", friendProfileId: id, friendProfileScope: .community, createdAt: "2026-10-29T00:00:00Z", profile: SocialProfileCard(profileId: id, displayName: id))
}

private actor Pages {
    private(set) var calls = 0
    private let pages: [[FriendItem]]

    init(_ pages: [[FriendItem]]) {
        self.pages = pages
    }

    func next() -> ListWithTotal<FriendItem> {
        defer { calls += 1 }
        let items = pages[min(calls, pages.count - 1)]
        return ListWithTotal(items: items, total: items.count)
    }
}

struct SocialLocalStoreTests {
    @Test func unfetchedListIsNilThenRowsInServerOrder() async throws {
        let local = SocialLocalStore(database: try .inMemory())
        var iterator = local.observeConnections("me", .friends).makeAsyncIterator()
        #expect(await iterator.next() == .some(nil))
        try await local.replaceConnections("me", .friends, ListWithTotal(items: [friend("b"), friend("a")], total: 2))
        #expect(await iterator.next()??.map(\.friendProfileId) == ["b", "a"])
    }

    @Test func removeAndClearOnlyTouchTheirRows() async throws {
        let database = try PulsoDatabase.inMemory()
        let local = SocialLocalStore(database: database)
        try await local.replaceConnections("me", .friends, ListWithTotal(items: [friend("a"), friend("b")], total: 2))
        try await local.replaceConnections("other", .friends, ListWithTotal(items: [friend("c")], total: 1))
        try await local.removeConnection("me", .friend, "a")
        var mine = local.observeConnections("me", .friends).makeAsyncIterator()
        #expect(await mine.next()??.map(\.friendProfileId) == ["b"])
        try await database.clearAll()
        var other = local.observeConnections("other", .friends).makeAsyncIterator()
        #expect(await other.next() == .some(nil))
    }
}

struct PersistedQueryTests {
    @Test func streamShowsLocalRowsThenRefetchesOnInvalidate() async throws {
        let local = SocialLocalStore(database: try .inMemory())
        let bus = EventBroadcast<Void>()
        let pages = Pages([[friend("a")], [friend("a"), friend("b")]])
        let query = PersistedQuery<String, ListWithTotal<FriendItem>, [FriendItem]>(
            invalidates: { bus.signals { _ in true } },
            fetcher: { _ in await pages.next() },
            reader: { owner in local.observeConnections(owner, .friends) },
            writer: { owner, page in try await local.replaceConnections(owner, .friends, page) },
            delete: { owner in try await local.clearConnections(owner, .friends) },
            deleteAll: { try await local.clearKind(.friend) }
        )
        var seen: [[String]] = []
        for await response in query.stream("me") {
            guard case let .data(items) = response else { continue }
            seen.append(items.map(\.friendProfileId))
            if seen.count == 1 { bus.emit(()) }
            if items.count == 2 { break }
        }
        #expect(seen.first == ["a"])
        #expect(seen.last == ["a", "b"])
        #expect(try await query.get("me").count == 2)
        #expect(await pages.calls == 2)
    }
}

@MainActor
struct MediatedListTests {
    @Test func pagesFillTheLocalTableAndTheListReadsIt() async throws {
        let local = SocialLocalStore(database: try .inMemory())
        let all = (0 ..< 5).map { friend("p\($0)") }
        let list = MediatedList<FriendItem>(pageSize: 2, reader: { local.observeConnections("me", .friends) }) { offset, limit in
            let items = Array(all[offset ..< min(offset + limit, all.count)])
            let page = ListWithTotal(items: items, total: all.count)
            if offset == 0 {
                try await local.replaceConnections("me", .friends, page)
            } else {
                try await local.appendConnections("me", .friends, items, start: offset, total: all.count)
            }
            return nextOffset(after: offset, count: items.count, total: all.count)
        }
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        try await waitUntil { list.items.count == 2 }
        list.loadMore()
        try await waitUntil { list.items.count == 4 }
        list.loadMore()
        try await waitUntil { list.items.count == 5 && list.endReached }
        #expect(list.items.map(\.friendProfileId) == all.map(\.friendProfileId))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}


struct LocalDataTests {
    @Test func tableSourceCountsAndClearsRows() async throws {
        let database = try PulsoDatabase.inMemory()
        let local = SocialLocalStore(database: database)
        try await local.replaceConnections("me", .friends, ListWithTotal(items: [friend("a"), friend("b")], total: 2))
        let source = DatabaseTableDataSource(database: database, kind: .socialConnections, table: SocialConnectionRecord.databaseTableName)
        #expect(try await source.usage() == LocalDataUsage(count: 2, bytes: nil))
        try await source.clear()
        #expect(try await source.usage() == LocalDataUsage(count: 0, bytes: nil))
    }

    @Test func serviceListsKindsInPageOrder() throws {
        let database = try PulsoDatabase.inMemory()
        let defaults = UserDefaults(suiteName: "local-data-test")!
        let service = LocalDataService(sources: database.localDataSources(wallpapers: ChatWallpaperStore(defaults: defaults)).reversed())
        #expect(service.kinds == [.chatMessages, .conversations, .notifications, .socialConnections, .friendRequests, .profileCards, .chatWallpapers])
    }
}

struct DeepLinkPathTests {
    @Test func parsesSegmentsAndQueryOfOwnScheme() throws {
        let link = try #require(DeepLinkPath(URL(string: "youloopy://open/panel/venue-book/v1?sport=tennis")!, scheme: "youloopy"))
        #expect(link.segments == ["panel", "venue-book", "v1"])
        #expect(link.query["sport"] == "tennis")
    }

    @Test func rejectsOtherSchemeOrHost() {
        #expect(DeepLinkPath(URL(string: "youneary://open/panel/x")!, scheme: "youloopy") == nil)
        #expect(DeepLinkPath(URL(string: "youloopy://share/panel/x")!, scheme: "youloopy") == nil)
    }

    @Test func siblingBuildsDeepLinkAndWebURL() {
        let app = SiblingApp(scheme: "youneary", webOrigin: "https://pulsonear.com")
        #expect(app.deepLink("/panel/venue-detail/v1")?.absoluteString == "youneary://open/panel/venue-detail/v1")
        #expect(app.webURL("/panel/venue-detail/v1")?.absoluteString == "https://pulsonear.com/panel/venue-detail/v1")
    }
}
