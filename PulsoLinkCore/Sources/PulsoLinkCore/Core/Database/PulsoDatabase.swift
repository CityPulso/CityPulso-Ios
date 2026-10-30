import Foundation
import GRDB

/**
 * App 的本地库（Android `PulsoLinkDatabase`，Room）：离线优先的列表以这里为准，网络只负责刷新。
 * 表结构由 [migrator] 逐版建立；登出时 [clearAll] 清空全部业务表。
 */
public final class PulsoDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /** 磁盘上的库：`Application Support/<name>.sqlite`。 */
    public convenience init(name: String) throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try self.init(writer: DatabasePool(path: directory.appendingPathComponent("\(name).sqlite").path))
    }

    /** 测试用的内存库。 */
    public static func inMemory() throws -> PulsoDatabase {
        try PulsoDatabase(writer: DatabaseQueue())
    }

    /** 登出：业务表全部清空（Android 登出时删整个 Room 库）。 */
    public func clearAll() async throws {
        try await writer.write { db in
            for table in Self.tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    private static let tables = [
        RemoteKeyRecord.databaseTableName, SocialConnectionRecord.databaseTableName, FriendRequestRecord.databaseTableName,
        ConversationRecord.databaseTableName, NotificationRecord.databaseTableName,
    ]

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: RemoteKeyRecord.databaseTableName) { t in
                t.column("ownerProfileId", .text).notNull()
                t.column("listKey", .text).notNull()
                t.column("nextOffset", .integer)
                t.column("total", .integer).notNull()
                t.column("fetchedAt", .double).notNull()
                t.primaryKey(["ownerProfileId", "listKey"])
            }
            try db.create(table: SocialConnectionRecord.databaseTableName) { t in
                t.column("ownerProfileId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("profileId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("payloadJson", .text).notNull()
                t.primaryKey(["ownerProfileId", "kind", "profileId"])
            }
            try db.create(index: "social_connections_order", on: SocialConnectionRecord.databaseTableName, columns: ["ownerProfileId", "kind", "position"])
            try db.create(table: FriendRequestRecord.databaseTableName) { t in
                t.column("ownerProfileId", .text).notNull()
                t.column("listKey", .text).notNull()
                t.column("friendRequestId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("payloadJson", .text).notNull()
                t.primaryKey(["ownerProfileId", "listKey", "friendRequestId"])
            }
            try db.create(index: "friend_requests_order", on: FriendRequestRecord.databaseTableName, columns: ["ownerProfileId", "listKey", "position"])
            try db.create(table: ConversationRecord.databaseTableName) { t in
                t.column("ownerProfileId", .text).notNull()
                t.column("conversationId", .text).notNull()
                t.column("isGroup", .boolean).notNull()
                t.column("position", .integer).notNull()
                t.column("payloadJson", .text).notNull()
                t.primaryKey(["ownerProfileId", "conversationId"])
            }
            try db.create(index: "conversations_order", on: ConversationRecord.databaseTableName, columns: ["ownerProfileId", "isGroup", "position"])
            try db.create(table: NotificationRecord.databaseTableName) { t in
                t.column("ownerProfileId", .text).notNull()
                t.column("notificationId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("readAt", .text)
                t.column("payloadJson", .text).notNull()
                t.primaryKey(["ownerProfileId", "notificationId"])
            }
            try db.create(index: "notifications_order", on: NotificationRecord.databaseTableName, columns: ["ownerProfileId", "position"])
        }
        return migrator
    }
}

/** 一份已缓存列表拉到了哪里（Android `RemoteKeyEntity`）；有这行 = 这份列表至少拉过一次。 */
struct RemoteKeyRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "remote_keys"

    var ownerProfileId: String
    var listKey: String
    var nextOffset: Int?
    var total: Int
    var fetchedAt: Double
}

/** 本地行里的 JSON 载荷：DTO 自己的 wire 编码。 */
enum LocalPayload {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

extension DatabaseReader {
    /** 观察一条查询，每次相关表变化就推一次（GRDB `ValueObservation`）；读失败时结束。 */
    func observe<Value: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> Value) -> AsyncStream<Value> {
        let values = ValueObservation.tracking(fetch).values(in: self)
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await value in values {
                        continuation.yield(value)
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/** 登出时清空本地库（Android 登出删 Room 库）。 */
struct LocalDatabaseClearable: LogoutClearable {
    let database: PulsoDatabase

    func onLogout() async throws {
        try await database.clearAll()
    }
}
