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
