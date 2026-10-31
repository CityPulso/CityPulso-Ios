import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 可以分享进聊天的一场活动（Android `ChatEventPickRow`）。 */
struct ChatEventPickRow: Identifiable, Hashable {
    let eventId: String
    let sport: LoopSport
    let startsAt: String
    let title: String
    let imageKey: String?
    let hostProfileId: String

    var id: String { "\(sport.rawValue):\(eventId)" }
}

/** 选一场活动分享进会话（Android `ChatEventPickerViewModel`）：我发起的，或我参加的（所有运动一起，最新的在前）。 */
@MainActor
@Observable
final class ChatEventPickerModel {
    private static let limit = 100

    let conversationId: String
    let hosted: Bool
    private(set) var events = Loadable<[ChatEventPickRow]>()

    @ObservationIgnored @Injected(\.loopSportServices) private var services
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.chatShareDraftStore) private var drafts
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(conversationId: String, hosted: Bool) {
        self.conversationId = conversationId
        self.hosted = hosted
    }

    func coverURL(_ imageId: String?) -> URL? { ImageURLs.image(imageId, base: config.apiBaseURL) }

    func load() async {
        events.isLoading = true
        events.error = nil
        let session = sessionStore.state.value
        let hosted = hosted
        let limit = Self.limit
        do {
            // 每个运动一个 main actor 任务（TaskGroup + @MainActor 子任务会让隔离检查器内部报错，同 `concurrently`）。
            let tasks = services.values.map { service in
                Task { @MainActor () throws -> [ChatEventPickRow] in
                    if hosted {
                        try await service.freshHostedEvents(accountId: session.currentAccountId, profileId: session.currentProfileId, hostedProfileId: session.currentProfileId, limit: limit)
                        let items = await Self.first(service.hostedEvents(accountId: session.currentAccountId, profileId: session.currentProfileId, hostedProfileId: session.currentProfileId, limit: limit))
                        return items.map { ChatEventPickRow(eventId: $0.id, sport: $0.sport, startsAt: $0.startsAt, title: $0.title ?? "", imageKey: $0.coverImageId, hostProfileId: session.currentProfileId) }
                    } else {
                        let query = SportRegistrationsQuery(accountId: session.currentAccountId, profileId: session.currentProfileId, limit: limit, excludeHosted: true)
                        try await service.freshMyRegistrations(query)
                        let items = await Self.first(service.myRegistrations(query))
                        return items.map { ChatEventPickRow(eventId: $0.id, sport: $0.sport, startsAt: $0.startsAt, title: $0.title ?? "", imageKey: $0.coverImageId, hostProfileId: $0.profileId ?? "") }
                    }
                }
            }
            var rows: [ChatEventPickRow] = []
            for task in tasks { rows += try await task.value }
            events = Loadable(data: sortedByStartsAt(rows, startsAt: \.startsAt, id: \.eventId, descending: true), isLoading: false)
        } catch {
            events = Loadable(data: events.data, isLoading: false, error: UiError(error))
        }
    }

    /** 查询流里第一份数据（fresh 之后缓存里就是最新的）。 */
    private static func first<T>(_ stream: AsyncStream<QueryResponse<[T]>>) async -> [T] {
        for await response in stream {
            if case let .data(items) = response { return items }
        }
        return []
    }

    func pick(_ row: ChatEventPickRow) {
        drafts.emit(.card(conversationId: conversationId, type: .eventShare, card: ChatSharedCardContent(
            product: .loop,
            targetId: row.eventId,
            subtype: row.sport.eventType.rawValue,
            title: row.title,
            subtitle: DateTimeFormatters.parseInstant(row.startsAt).map { $0.formatted(date: .abbreviated, time: .shortened) },
            imageKey: row.imageKey,
            hostProfileId: row.hostProfileId,
            hostProfileScope: .community
        )))
    }
}

/** 分享活动（Android `ChatEventPickerScreen`）。 */
struct ChatEventPickerView: View {
    @State private var model: ChatEventPickerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(conversationId: String, hosted: Bool) {
        _model = State(initialValue: ChatEventPickerModel(conversationId: conversationId, hosted: hosted))
    }

    var body: some View {
        Group {
            if let rows = model.events.data {
                if rows.isEmpty {
                    PulsoEmptyState(Text("shell_chat_event_picker_empty"), style: .calendar)
                } else {
                    List(rows) { row in
                        Button {
                            model.pick(row)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                SportCover(url: model.coverURL(row.imageKey), sport: row.sport, iconSize: 22)
                                    .frame(width: 56, height: 56)
                                    .clipShape(.rect(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: row.title).font(.headline).lineLimit(1)
                                    Text(verbatim: [String(localized: row.sport.labelResource), DateTimeFormatters.monthDayTime(row.startsAt, locale: locale)].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let error = model.events.error {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle((model.hosted ? "shell_chat_event_picker_hosted" : "shell_chat_event_picker_shared") as LocalizedStringKey)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}

/** 分享收藏（Android `ChatFavoritePickerViewModel`）：收藏的场馆建筑、球馆；帖子和论坛随第 11 组。 */
@MainActor
@Observable
final class ChatFavoritePickerModel {
    let conversationId: String
    var tab = ChatFavoriteTab.buildings
    let buildings: PagedList<BuildingFavoriteItem, Int>
    let venues: PagedList<VenueFavoriteItem, Int>
    let posts: PagedList<PostCard, Int>
    let forums: PagedList<ForumFavorite, Int>

    @ObservationIgnored @Injected(\.chatShareDraftStore) private var drafts
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(conversationId: String) {
        self.conversationId = conversationId
        let favorites = Container.shared.favoriteService()
        buildings = favorites.pageBuildings(BuildingFavoritesFilter(buildingTypes: BuildingType.loop.map(\.rawValue)))
        venues = favorites.pageVenues(VenueFavoritesFilter())
        let discussion = Container.shared.discussionService()
        posts = discussion.pageBookmarkedPosts()
        forums = discussion.pageFavoriteForums(nil)
    }

    /** 帖子的标题；没有标题的取正文开头。 */
    static func postTitle(_ post: PostCard) -> String {
        post.title.isEmpty ? String(post.contentText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) : post.title
    }

    func imageURL(_ imageId: String?) -> URL? { ImageURLs.image(imageId, base: config.apiBaseURL) }

    func pick(_ building: BuildingFavoriteItem) {
        drafts.emit(.card(conversationId: conversationId, type: .buildingShare, card: ChatSharedCardContent(
            targetId: building.buildingId, title: building.name, subtitle: building.address.isEmpty ? nil : building.address, imageKey: building.coverImageId
        )))
    }

    func pick(_ venue: VenueFavoriteItem) {
        drafts.emit(.card(conversationId: conversationId, type: .venueShare, card: ChatSharedCardContent(
            product: .loop, targetId: venue.venueId, subtype: venue.venueSports.first?.rawValue,
            title: venue.building.name, subtitle: venue.building.address.isEmpty ? nil : venue.building.address, imageKey: venue.coverImageId
        )))
    }

    func pick(_ post: PostCard) {
        let forum = post.forums.first?.forumName
        drafts.emit(.card(conversationId: conversationId, type: .postShare, card: ChatSharedCardContent(
            product: .loop, targetId: post.id, title: Self.postTitle(post),
            subtitle: (forum?.isEmpty ?? true) ? nil : forum, imageKey: post.previewImageIds.first
        )))
    }

    func pick(_ forum: ForumFavorite) {
        drafts.emit(.card(conversationId: conversationId, type: .forumShare, card: ChatSharedCardContent(
            product: .loop, targetId: forum.forumId, title: forum.name,
            subtitle: forum.description.isEmpty ? nil : forum.description, imageKey: forum.coverImageId ?? forum.avatarImageId
        )))
    }
}

/** 分享收藏（Android `ChatFavoritePickerScreen`）：场馆建筑 / 球馆 / 帖子 / 论坛四个标签。 */
struct ChatFavoritePickerView: View {
    @State private var model: ChatFavoritePickerModel
    @Environment(\.dismiss) private var dismiss

    init(conversationId: String) {
        _model = State(initialValue: ChatFavoritePickerModel(conversationId: conversationId))
    }

    var body: some View {
        VStack(spacing: 0) {
            PulsoUnderlineTabRow([ChatFavoriteTab.buildings, .venues, .posts, .forums], selection: $model.tab) { tab in
                switch tab {
                case .buildings: Text("shell_chat_favorite_picker_buildings")
                case .venues: Text("shell_chat_favorite_picker_venues")
                case .posts: Text("shell_chat_favorite_picker_posts")
                case .forums: Text("shell_chat_favorite_picker_forums")
                }
            }
            switch model.tab {
            case .buildings:
                pickList(model.buildings, empty: "shell_chat_favorite_picker_empty_buildings") { item in
                    row("building.2", model.imageURL(item.coverImageId), item.name, item.address) { model.pick(item); dismiss() }
                }
            case .venues:
                pickList(model.venues, empty: "shell_chat_favorite_picker_empty_venues") { item in
                    row("sportscourt", model.imageURL(item.coverImageId), item.building.name, item.building.address) { model.pick(item); dismiss() }
                }
            case .posts:
                pickList(model.posts, empty: "shell_chat_favorite_picker_empty_posts") { item in
                    row("doc.text", model.imageURL(item.previewImageIds.first), ChatFavoritePickerModel.postTitle(item), item.forums.first?.forumName ?? "") { model.pick(item); dismiss() }
                }
            case .forums:
                pickList(model.forums, empty: "shell_chat_favorite_picker_empty_forums") { item in
                    row("bubble.left.and.bubble.right", model.imageURL(item.avatarImageId ?? item.coverImageId), item.name, item.description) { model.pick(item); dismiss() }
                }
            }
        }
        .navigationTitle("shell_chat_favorite_picker_title")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func pickList<Item: Identifiable & Sendable, Row: View>(_ list: PagedList<Item, Int>, empty: LocalizedStringKey, @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        Group {
            if list.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = list.error {
                PulsoLoadErrorView(error) { Task { await list.refresh() } }
            } else if list.isEmpty {
                PulsoEmptyState(Text(empty))
            } else {
                List(list.items) { item in
                    row(item).onAppear { if item.id == list.items.last?.id { list.loadMore() } }
                }
            }
        }
        .task { await list.observe() }
    }

    private func row(_ symbol: String, _ image: URL?, _ title: String, _ subtitle: String, onPick: @escaping () -> Void) -> some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary)
                    if let image { PulsoRemoteImage(url: image) } else { Image(systemName: symbol).foregroundStyle(.secondary) }
                }
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !subtitle.isEmpty { Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

extension BuildingFavoriteItem: Identifiable {}
extension VenueFavoriteItem: Identifiable {}
