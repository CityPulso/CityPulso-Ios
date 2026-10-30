import Foundation
import GRDB

/** 公开资料卡（昵称 + 头像），聊天发送者、会话对方、社交行共用（Android `ProfileCardEntity`）；登出时随本地库清掉。 */
public struct ProfileCard: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "profile_cards"

    public var profileId: String
    public var displayName: String?
    public var avatarImageId: String?
    public var fetchedAt: Double
}

/** 本地缓存的公开资料卡（Android `ProfileCardRepository`）：页面观察一组 id、调一次 [ensure]，只有没缓存的才并发拉网络。 */
public struct ProfileCardRepository: Sendable {
    private let auth: AuthRepository
    private let database: PulsoDatabase

    public init(auth: AuthRepository, database: PulsoDatabase) {
        self.auth = auth
        self.database = database
    }

    public func observe(_ ids: [String]) -> AsyncStream<[String: ProfileCard]> {
        let wanted = Array(Set(ids))
        return database.writer.observe { db in
            let rows = try ProfileCard.filter(wanted.contains(Column("profileId"))).fetchAll(db)
            return Dictionary(rows.map { ($0.profileId, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /** 已经知道的卡（比如当前身份）直接写，不拉网络。 */
    public func put(_ profileId: String, displayName: String?, avatarImageId: String?) async throws {
        let card = ProfileCard(profileId: profileId, displayName: displayName, avatarImageId: avatarImageId, fetchedAt: Date().timeIntervalSince1970)
        try await database.writer.write { db in try card.upsert(db) }
    }

    /** 拉还没缓存的卡；失败的 id 留着不写，下次再试。 */
    public func ensure(_ ids: [String]) async throws {
        let wanted = Array(Set(ids.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
        guard !wanted.isEmpty else { return }
        let cached = try await database.writer.read { db in
            try Set(ProfileCard.filter(wanted.contains(Column("profileId"))).fetchAll(db).map(\.profileId))
        }
        let missing = wanted.filter { !cached.contains($0) }
        guard !missing.isEmpty else { return }
        let auth = auth
        let fetched = await withTaskGroup(of: ProfileCard?.self) { group in
            for id in missing {
                group.addTask {
                    guard let card = try? await auth.getPublicProfileCard(profileId: id) else { return nil }
                    return ProfileCard(profileId: id, displayName: card.displayName, avatarImageId: card.avatarImageId, fetchedAt: Date().timeIntervalSince1970)
                }
            }
            var out: [ProfileCard] = []
            for await card in group { if let card { out.append(card) } }
            return out
        }
        guard !fetched.isEmpty else { return }
        try await database.writer.write { db in
            for card in fetched { try card.upsert(db) }
        }
    }
}
