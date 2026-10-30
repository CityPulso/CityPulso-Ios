import Foundation
import GRDB

/** 私聊或群聊列表里的一行，按服务端顺序（Android `ConversationEntity`）。 */
struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"

    var ownerProfileId: String
    var conversationId: String
    var isGroup: Bool
    var position: Int
    /** `ConversationDirectItem` 或 `ConversationGroupItem` 的 JSON。 */
    var payloadJson: String
}

/** 收件箱里的一条通知，按服务端顺序（Android `NotificationEntity`）；[readAt] 管「未读」筛选。 */
struct NotificationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notifications"

    var ownerProfileId: String
    var notificationId: String
    var position: Int
    var readAt: String?
    var payloadJson: String
}

/** 通信列表的本地一侧（Android `CommunicationLocalStore`）：会话列表与通知收件箱。 */
public struct CommunicationLocalStore: Sendable {
    private static let notificationsKey = "notifications"
    private let database: PulsoDatabase

    public init(database: PulsoDatabase) {
        self.database = database
    }

    /* ------------------------------ conversations ------------------------------ */

    public func observeDirect(_ owner: String) -> AsyncStream<[ConversationDirectItem]?> { observeList(owner, isGroup: false) }
    public func observeGroups(_ owner: String) -> AsyncStream<[ConversationGroupItem]?> { observeList(owner, isGroup: true) }

    public func replaceDirect(_ owner: String, _ page: ListWithTotal<ConversationDirectItem>) async throws {
        try await replaceList(owner, isGroup: false, total: page.total, rows: page.items.map { ($0.conversationId, try LocalPayload.encode($0)) })
    }

    public func replaceGroups(_ owner: String, _ page: ListWithTotal<ConversationGroupItem>) async throws {
        try await replaceList(owner, isGroup: true, total: page.total, rows: page.items.map { ($0.conversationId, try LocalPayload.encode($0)) })
    }

    public func clearConversations(_ owner: String, isGroup: Bool) async throws {
        let key = Self.conversationListKey(isGroup)
        try await database.writer.write { db in
            _ = try ConversationRecord.filter(Column("ownerProfileId") == owner && Column("isGroup") == isGroup).deleteAll(db)
            _ = try RemoteKeyRecord.deleteOne(db, key: ["ownerProfileId": owner, "listKey": key])
        }
    }

    public func clearAllConversations() async throws {
        try await database.writer.write { db in _ = try ConversationRecord.deleteAll(db) }
    }

    private func observeList<T: Decodable & Sendable>(_ owner: String, isGroup: Bool) -> AsyncStream<[T]?> {
        let key = Self.conversationListKey(isGroup)
        return database.writer.observe { db -> [T]? in
            guard try RemoteKeyRecord.fetchOne(db, key: ["ownerProfileId": owner, "listKey": key]) != nil else { return nil }
            return try ConversationRecord
                .filter(Column("ownerProfileId") == owner && Column("isGroup") == isGroup)
                .order(Column("position"))
                .fetchAll(db)
                .map { try LocalPayload.decode(T.self, $0.payloadJson) }
        }
    }

    /** 整页替换：服务端列表为准，消失的会话一起删掉。 */
    private func replaceList(_ owner: String, isGroup: Bool, total: Int, rows: [(String, String)]) async throws {
        let records = rows.enumerated().map { index, row in
            ConversationRecord(ownerProfileId: owner, conversationId: row.0, isGroup: isGroup, position: index, payloadJson: row.1)
        }
        let key = RemoteKeyRecord(ownerProfileId: owner, listKey: Self.conversationListKey(isGroup), nextOffset: nil, total: total, fetchedAt: Date().timeIntervalSince1970)
        try await database.writer.write { db in
            _ = try ConversationRecord.filter(Column("ownerProfileId") == owner && Column("isGroup") == isGroup).deleteAll(db)
            for record in records { try record.upsert(db) }
            try key.upsert(db)
        }
    }

    private static func conversationListKey(_ isGroup: Bool) -> String { isGroup ? "conversations:group" : "conversations:direct" }

    /* ------------------------------ notifications ------------------------------ */

    /** 收件箱（本地行）；[unreadOnly] 在本地行上筛，换筛选不重拉、离线也能用。本地 [readAt] 优先于载荷，直到下次拉取。 */
    public func observeNotifications(_ owner: String, unreadOnly: Bool) -> AsyncStream<[NotificationInboxItem]?> {
        let key = Self.notificationsKey
        return database.writer.observe { db -> [NotificationInboxItem]? in
            guard try RemoteKeyRecord.fetchOne(db, key: ["ownerProfileId": owner, "listKey": key]) != nil else { return nil }
            var request = NotificationRecord.filter(Column("ownerProfileId") == owner)
            if unreadOnly { request = request.filter(Column("readAt") == nil) }
            return try request.order(Column("position")).fetchAll(db).map { record in
                var item = try LocalPayload.decode(NotificationInboxItem.self, record.payloadJson)
                item.readAt = record.readAt
                return item
            }
        }
    }

    /** 写一页通知；offset 0 时整份替换。返回下一页 offset。 */
    public func writeNotifications(_ owner: String, _ page: ListWithTotal<NotificationInboxItem>, start: Int) async throws -> Int? {
        let records = try page.items.enumerated().map { index, item in
            try NotificationRecord(ownerProfileId: owner, notificationId: item.id, position: start + index, readAt: item.readAt, payloadJson: LocalPayload.encode(item))
        }
        let following = nextOffset(after: start, count: page.items.count, total: page.total)
        let key = RemoteKeyRecord(ownerProfileId: owner, listKey: Self.notificationsKey, nextOffset: following, total: page.total, fetchedAt: Date().timeIntervalSince1970)
        try await database.writer.write { db in
            if start == 0 { _ = try NotificationRecord.filter(Column("ownerProfileId") == owner).deleteAll(db) }
            for record in records { try record.upsert(db) }
            try key.upsert(db)
        }
        return following
    }

    /** 本地缓存里的未读数（「未读」筛选上的数字）。 */
    public func observeUnreadCount(_ owner: String) -> AsyncStream<Int> {
        database.writer.observe { db in
            try NotificationRecord.filter(Column("ownerProfileId") == owner && Column("readAt") == nil).fetchCount(db)
        }
    }

    public func markNotificationRead(_ owner: String, _ id: String) async throws {
        let now = DateTimeFormatters.rfc3339(Date())
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE notifications SET readAt = ? WHERE ownerProfileId = ? AND notificationId = ?", arguments: [now, owner, id])
        }
    }

    public func markAllNotificationsRead(_ owner: String) async throws {
        let now = DateTimeFormatters.rfc3339(Date())
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE notifications SET readAt = ? WHERE ownerProfileId = ? AND readAt IS NULL", arguments: [now, owner])
        }
    }
}
