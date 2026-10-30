import Foundation
import GRDB

/** 关系列表是哪一份（Android `SocialConnectionKind`），按 [rawValue] 存。 */
public enum SocialConnectionKind: String, Sendable {
    case friend
    case following
    case follower
    case blocked
}

/** 好友 / 关注 / 粉丝 / 拉黑列表里的一行，按服务端顺序（Android `SocialConnectionEntity`）。 */
struct SocialConnectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "social_connections"

    var ownerProfileId: String
    var kind: String
    var profileId: String
    var position: Int
    /** `FriendItem` / `FollowingItem` / `FollowerItem` / `BlockedItem` 的 JSON。 */
    var payloadJson: String
}

/** 某个筛选下的一条好友请求，按服务端顺序（Android `FriendRequestEntity`）。 */
struct FriendRequestRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "friend_requests"

    var ownerProfileId: String
    /** 拉这份列表时用的方向 / 状态筛选。 */
    var listKey: String
    var friendRequestId: String
    var position: Int
    var payloadJson: String
}

/** 一种关系列表怎样落到 `social_connections`（Android `SocialConnectionSpec`）。 */
public struct SocialConnectionSpec<T: Codable & Sendable>: Sendable {
    public let kind: SocialConnectionKind
    let profileIdOf: @Sendable (T) -> String

    var listKey: String { "social:\(kind.rawValue)" }
}

public extension SocialConnectionSpec where T == FriendItem {
    static var friends: Self { Self(kind: .friend) { $0.friendProfileId } }
}

public extension SocialConnectionSpec where T == FollowingItem {
    static var following: Self { Self(kind: .following) { $0.followingProfileId } }
}

public extension SocialConnectionSpec where T == FollowerItem {
    static var followers: Self { Self(kind: .follower) { $0.followerProfileId } }
}

public extension SocialConnectionSpec where T == BlockedItem {
    static var blocked: Self { Self(kind: .blocked) { $0.blockedProfileId } }
}

/** 社交列表的本地一侧（Android `SocialLocalStore`）：关系列表与好友请求。 */
public struct SocialLocalStore: Sendable {
    private let database: PulsoDatabase

    public init(database: PulsoDatabase) {
        self.database = database
    }

    /* ------------------------------ relation lists ------------------------------ */

    /** 第一页（选择器用）；还没拉过时为 nil。 */
    public func observeConnections<T>(_ owner: String, _ spec: SocialConnectionSpec<T>) -> AsyncStream<[T]?> {
        let kind = spec.kind.rawValue
        let listKey = spec.listKey
        return database.writer.observe { db -> [T]? in
            guard try RemoteKeyRecord.fetchOne(db, key: ["ownerProfileId": owner, "listKey": listKey]) != nil else { return nil }
            return try SocialConnectionRecord
                .filter(Column("ownerProfileId") == owner && Column("kind") == kind)
                .order(Column("position"))
                .fetchAll(db)
                .map { try LocalPayload.decode(T.self, $0.payloadJson) }
        }
    }

    /** 整份替换成这一页，并记下拉到了哪里。 */
    public func replaceConnections<T>(_ owner: String, _ spec: SocialConnectionSpec<T>, _ page: ListWithTotal<T>) async throws {
        let rows = try rows(page.items, owner: owner, spec: spec, start: 0)
        let key = RemoteKeyRecord(
            ownerProfileId: owner, listKey: spec.listKey,
            nextOffset: page.items.count < page.total ? page.items.count : nil,
            total: page.total, fetchedAt: Date().timeIntervalSince1970
        )
        let kind = spec.kind.rawValue
        try await database.writer.write { db in
            try SocialConnectionRecord.filter(Column("ownerProfileId") == owner && Column("kind") == kind).deleteAll(db)
            for row in rows { try row.upsert(db) }
            try key.upsert(db)
        }
    }

    /** 分页继续往后写（关系列表翻页）。 */
    public func appendConnections<T>(_ owner: String, _ spec: SocialConnectionSpec<T>, _ items: [T], start: Int, total: Int) async throws {
        let rows = try rows(items, owner: owner, spec: spec, start: start)
        let reached = start + items.count
        let key = RemoteKeyRecord(
            ownerProfileId: owner, listKey: spec.listKey,
            nextOffset: !items.isEmpty && reached < total ? reached : nil,
            total: total, fetchedAt: Date().timeIntervalSince1970
        )
        try await database.writer.write { db in
            for row in rows { try row.upsert(db) }
            try key.upsert(db)
        }
    }

    public func clearConnections<T>(_ owner: String, _ spec: SocialConnectionSpec<T>) async throws {
        let kind = spec.kind.rawValue
        let listKey = spec.listKey
        try await database.writer.write { db in
            try SocialConnectionRecord.filter(Column("ownerProfileId") == owner && Column("kind") == kind).deleteAll(db)
            _ = try RemoteKeyRecord.deleteOne(db, key: ["ownerProfileId": owner, "listKey": listKey])
        }
    }

    public func clearKind(_ kind: SocialConnectionKind) async throws {
        try await database.writer.write { db in
            _ = try SocialConnectionRecord.filter(Column("kind") == kind.rawValue).deleteAll(db)
        }
    }

    /** 乐观删除（解除拉黑、删好友），之后服务端列表再重拉。 */
    public func removeConnection(_ owner: String, _ kind: SocialConnectionKind, _ profileId: String) async throws {
        try await database.writer.write { db in
            _ = try SocialConnectionRecord.deleteOne(db, key: ["ownerProfileId": owner, "kind": kind.rawValue, "profileId": profileId])
        }
    }

    private func rows<T>(_ items: [T], owner: String, spec: SocialConnectionSpec<T>, start: Int) throws -> [SocialConnectionRecord] {
        try items.enumerated().map { index, item in
            try SocialConnectionRecord(
                ownerProfileId: owner, kind: spec.kind.rawValue, profileId: spec.profileIdOf(item),
                position: start + index, payloadJson: LocalPayload.encode(item)
            )
        }
    }

    /* ------------------------------ friend requests ------------------------------ */

    public func observeRequests(_ owner: String, _ listKey: String) -> AsyncStream<[FriendRequestItem]?> {
        let key = Self.requestKey(listKey)
        return database.writer.observe { db -> [FriendRequestItem]? in
            guard try RemoteKeyRecord.fetchOne(db, key: ["ownerProfileId": owner, "listKey": key]) != nil else { return nil }
            return try FriendRequestRecord
                .filter(Column("ownerProfileId") == owner && Column("listKey") == listKey)
                .order(Column("position"))
                .fetchAll(db)
                .map { try LocalPayload.decode(FriendRequestItem.self, $0.payloadJson) }
        }
    }

    public func replaceRequests(_ owner: String, _ listKey: String, _ page: ListWithTotal<FriendRequestItem>) async throws {
        let rows = try page.items.enumerated().map { index, item in
            try FriendRequestRecord(ownerProfileId: owner, listKey: listKey, friendRequestId: item.friendRequestId, position: index, payloadJson: LocalPayload.encode(item))
        }
        let key = RemoteKeyRecord(ownerProfileId: owner, listKey: Self.requestKey(listKey), nextOffset: nil, total: page.total, fetchedAt: Date().timeIntervalSince1970)
        try await database.writer.write { db in
            try FriendRequestRecord.filter(Column("ownerProfileId") == owner && Column("listKey") == listKey).deleteAll(db)
            for row in rows { try row.upsert(db) }
            try key.upsert(db)
        }
    }

    public func clearRequests(_ owner: String, _ listKey: String) async throws {
        let key = Self.requestKey(listKey)
        try await database.writer.write { db in
            try FriendRequestRecord.filter(Column("ownerProfileId") == owner && Column("listKey") == listKey).deleteAll(db)
            _ = try RemoteKeyRecord.deleteOne(db, key: ["ownerProfileId": owner, "listKey": key])
        }
    }

    public func clearAllRequests() async throws {
        try await database.writer.write { db in
            _ = try FriendRequestRecord.deleteAll(db)
        }
    }

    /** 接受 / 拒绝 / 撤回后的乐观删除。 */
    public func removeRequest(_ owner: String, _ friendRequestId: String) async throws {
        try await database.writer.write { db in
            _ = try FriendRequestRecord.filter(Column("ownerProfileId") == owner && Column("friendRequestId") == friendRequestId).deleteAll(db)
        }
    }

    private static func requestKey(_ listKey: String) -> String { "friend_requests:\(listKey)" }
}
