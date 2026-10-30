import Foundation
import GRDB

/** 存在这台设备上的一种数据，「清除本地数据」设置页按这个顺序列出（Android `LocalDataKind`）。 */
public enum LocalDataKind: CaseIterable, Sendable, Hashable {
    case chatMessages
    case conversations
    case notifications
    case socialConnections
    case friendRequests
    case profileCards
    case images
    case chatWallpapers
    case drafts

    /** 服务端的数据下次加载会回来；壁纸和草稿只在这台设备上。 */
    public var recoverable: Bool { self != .chatWallpapers && self != .drafts }
}

/** 一种数据占了多少：行数或文件数（[count]）和磁盘字节（[bytes]）；说不出来的是 nil。 */
public struct LocalDataUsage: Sendable, Hashable {
    public let count: Int?
    public let bytes: Int64?

    public init(count: Int?, bytes: Int64?) {
        self.count = count
        self.bytes = bytes
    }
}

/**
 * 设置页能量出大小、能清空的一个存储（Android `LocalDataSource`）。core 提供本地库的表和聊天壁纸，App 再加自己的
 * （图片缓存、草稿）。清除从不碰登录状态、设备 id、上次登录邮箱和偏好设置。
 */
public protocol LocalDataSource: Sendable {
    var kind: LocalDataKind { get }
    func usage() async throws -> LocalDataUsage
    func clear() async throws
}

/** 所有数据源，按种类（Android `LocalDataService`）。 */
public struct LocalDataService: Sendable {
    private let byKind: [LocalDataKind: any LocalDataSource]

    /** 这个 App 存的种类，按 [LocalDataKind] 的顺序。 */
    public let kinds: [LocalDataKind]

    public init(sources: [any LocalDataSource]) {
        let byKind = Dictionary(sources.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        self.byKind = byKind
        kinds = LocalDataKind.allCases.filter { byKind[$0] != nil }
    }

    public func usage(_ kind: LocalDataKind) async throws -> LocalDataUsage {
        try await byKind[kind]!.usage()
    }

    public func clear(_ kind: LocalDataKind) async throws {
        try await byKind[kind]!.clear()
    }

    public func clearAll() async throws {
        for kind in kinds { try await clear(kind) }
    }
}

/**
 * 本地库里的一张表。清空时连所有分页的 remote key 一起删，列表会重新从服务端拉，
 * 而不是相信一个指向已删除行的页码（Android `RoomTableDataSource`）。
 */
public struct DatabaseTableDataSource: LocalDataSource {
    public let kind: LocalDataKind
    private let database: PulsoDatabase
    private let table: String

    public init(database: PulsoDatabase, kind: LocalDataKind, table: String) {
        self.database = database
        self.kind = kind
        self.table = table
    }

    public func usage() async throws -> LocalDataUsage {
        let table = table
        let count = try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
        return LocalDataUsage(count: count, bytes: nil)
    }

    public func clear() async throws {
        let table = table
        // 一个事务里删，观察这张表的页面会看到变化。
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM \(table)")
            try db.execute(sql: "DELETE FROM \(RemoteKeyRecord.databaseTableName)")
        }
    }
}

/** 给会话挑的壁纸：这台设备上的文件。 */
public struct ChatWallpaperDataSource: LocalDataSource {
    public let kind = LocalDataKind.chatWallpapers
    private let store: ChatWallpaperStore

    public init(store: ChatWallpaperStore) {
        self.store = store
    }

    public func usage() async throws -> LocalDataUsage {
        let usage = store.usage()
        return LocalDataUsage(count: usage.count, bytes: usage.bytes)
    }

    public func clear() async throws {
        try await store.onLogout()
    }
}

extension PulsoDatabase {
    /** core 管的数据源：六张业务表和聊天壁纸（App 再加图片缓存和草稿）。 */
    public func localDataSources(wallpapers: ChatWallpaperStore) -> [any LocalDataSource] {
        let tables: [(LocalDataKind, String)] = [
            (.chatMessages, ChatMessageRecord.databaseTableName),
            (.conversations, ConversationRecord.databaseTableName),
            (.notifications, NotificationRecord.databaseTableName),
            (.socialConnections, SocialConnectionRecord.databaseTableName),
            (.friendRequests, FriendRequestRecord.databaseTableName),
            (.profileCards, ProfileCard.databaseTableName),
        ]
        return tables.map { DatabaseTableDataSource(database: self, kind: $0.0, table: $0.1) } + [ChatWallpaperDataSource(store: wallpapers)]
    }
}
