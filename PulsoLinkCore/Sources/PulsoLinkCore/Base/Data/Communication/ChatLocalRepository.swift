import Foundation
import GRDB

/** 一条消息在本地的发送状态（Android `ChatMessageStatus`）。 */
public enum ChatMessageStatus: String, Codable, Sendable {
    case sending
    case sent
    case failed
}

/** 本地的一条聊天消息（Android `ChatMessageEntity`）；乐观行以 clientMessageId 作主键。 */
struct ChatMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat_messages"

    var messageId: String
    /** 拉到这条消息的身份；别的身份的行永远不读。 */
    var ownerProfileId: String
    var conversationId: String
    var clientMessageId: String?
    var createdAtMillis: Double
    var deletedAt: String?
    var status: String
    /** `ChatMessageItem` 的 JSON。 */
    var payloadJson: String
}

/** 本地存的一条消息和它的发送状态。 */
public struct StoredChatMessage: Sendable, Hashable {
    public let item: ChatMessageItem
    public let status: ChatMessageStatus
    public let createdAtMillis: Double

    public var isSent: Bool { status == .sent }
}

/** 当前身份的本地聊天记录（Android `ChatLocalRepository`）。 */
public struct ChatLocalRepository: Sendable {
    private let database: PulsoDatabase
    private let sessionStore: AuthSessionStore

    public init(database: PulsoDatabase, sessionStore: AuthSessionStore) {
        self.database = database
        self.sessionStore = sessionStore
    }

    private var owner: String { sessionStore.state.value.currentProfileId }

    /** 一个会话里的全部本地消息，最新的在前。 */
    public func observe(_ conversationId: String) -> AsyncStream<[StoredChatMessage]> {
        let owner = owner
        return database.writer.observe { db in
            try ChatMessageRecord
                .filter(Column("ownerProfileId") == owner && Column("conversationId") == conversationId)
                .order(Column("createdAtMillis").desc)
                .fetchAll(db)
                .compactMap(Self.stored)
        }
    }

    /** 写入服务端的消息；先删掉这些消息已经确认的乐观行。 */
    public func upsertRemote(_ items: [ChatMessageItem]) async throws {
        guard !items.isEmpty else { return }
        let owner = owner
        let records = try items.map { try Self.record($0, owner: owner, status: .sent) }
        let clientIds = items.compactMap(\.clientMessageId)
        let serverIds = Set(items.map(\.messageId))
        try await database.writer.write { db in
            let confirmed = clientIds.filter { !serverIds.contains($0) }
            if !confirmed.isEmpty {
                _ = try ChatMessageRecord.filter(Column("ownerProfileId") == owner && confirmed.contains(Column("messageId"))).deleteAll(db)
            }
            for record in records { try record.upsert(db) }
        }
    }

    /** 正在发的消息先显示一行（主键是 clientId）。 */
    public func upsertOptimistic(_ item: ChatMessageItem) async throws {
        let record = try Self.record(item, owner: owner, status: .sending)
        try await database.writer.write { db in try record.upsert(db) }
    }

    public func markFailed(_ messageId: String) async throws {
        let owner = owner
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE chat_messages SET status = ? WHERE ownerProfileId = ? AND messageId = ?", arguments: [ChatMessageStatus.failed.rawValue, owner, messageId])
        }
    }

    public func markDeleted(_ messageId: String, deletedAt: String) async throws {
        let owner = owner
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE chat_messages SET deletedAt = ? WHERE ownerProfileId = ? AND messageId = ?", arguments: [deletedAt, owner, messageId])
        }
    }

    private static func record(_ item: ChatMessageItem, owner: String, status: ChatMessageStatus) throws -> ChatMessageRecord {
        ChatMessageRecord(
            messageId: item.messageId,
            ownerProfileId: owner,
            conversationId: item.conversationId,
            clientMessageId: item.clientMessageId,
            createdAtMillis: (DateTimeFormatters.parseInstant(item.createdAt) ?? Date()).timeIntervalSince1970 * 1000,
            deletedAt: item.deletedAt,
            status: status.rawValue,
            payloadJson: try LocalPayload.encode(item)
        )
    }

    /** 本地的 [deletedAt] 优先（撤回后马上生效）。 */
    private static func stored(_ record: ChatMessageRecord) -> StoredChatMessage? {
        guard var item = try? LocalPayload.decode(ChatMessageItem.self, record.payloadJson) else { return nil }
        item.deletedAt = record.deletedAt
        return StoredChatMessage(item: item, status: ChatMessageStatus(rawValue: record.status) ?? .sent, createdAtMillis: record.createdAtMillis)
    }
}
