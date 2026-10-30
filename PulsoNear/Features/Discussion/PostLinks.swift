import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 链接卡片上显示的：标题、一行说明、封面（Android `LinkCardInfo`）。 */
struct LinkCardInfo: Hashable, Sendable {
    let title: String
    let meta: String
    let coverImageId: String?
}

/** 链接卡片的状态：加载中、目标没了（或看不到）、好了。 */
enum LinkCardState: Hashable, Sendable {
    case loading
    case missing
    case ready(LinkCardInfo)
}

extension PostLinkType {
    /** 没有封面时卡片上的图标。 */
    var symbol: String {
        switch self {
        case .post: "doc.text"
        case .activity: "calendar"
        case .venue: "storefront"
        case .building: "building.2"
        }
    }
}

extension PostLink {
    /** 链接目标（类型 + id），页面上卡片缓存的 key。 */
    var key: String { "\(type.rawValue)/\(id)" }
}

extension PostDetail {
    var live: [PostPublication] { publications.filter { $0.status == .published } }
    var allowComments: Bool { live.contains { $0.allowComments } }
    var allowReposts: Bool { live.contains { $0.allowReposts } }
    /** 举报这篇帖子记在哪个论坛。 */
    var reportForumId: String? { live.first?.forumId }
}

/**
 * 读链接段落的目标（Android `PostLinkLoader`）：帖子、各活动类型的活动、门店、PulsoLink 的建筑；不存在或看不到时 nil。
 */
@MainActor
enum PostLinkLoader {
    static func load(_ link: PostLink) async -> LinkCardInfo? {
        let container = Container.shared
        do {
            switch link.type {
            case .post:
                let post = try await container.discussionService().post(link.id)
                return LinkCardInfo(
                    title: post.title,
                    meta: [post.author.displayName, post.publications.first?.forumName].compactMap { $0 }.joined(separator: " · "),
                    coverImageId: post.images.min { $0.sortOrder < $1.sortOrder }?.imageId
                )
            case .activity:
                guard let activityType = link.activityType, let service = container.nearActivityServices()[activityType] else { return nil }
                for await response in service.detail(activityId: link.id) {
                    switch response {
                    case .loading: continue
                    case let .data(detail):
                        return LinkCardInfo(
                            title: detail.activity.title,
                            meta: [DateTimeFormatters.monthDayTime(detail.activity.startsAt), detail.activity.venueName].compactMap { $0 }.joined(separator: " · "),
                            coverImageId: detail.imageIds.first
                        )
                    case .error: return nil
                    }
                }
                return nil
            case .venue:
                let venue = try await container.venueService().getVenue(link.id)
                return LinkCardInfo(title: venue.building.name, meta: venue.building.address, coverImageId: venue.images.min { $0.sortOrder < $1.sortOrder }?.imageId ?? venue.building.images.first?.imageId)
            case .building:
                let building = try await container.buildingService().getBuilding(id: link.id)
                return LinkCardInfo(title: building.name, meta: building.address, coverImageId: building.coverImageId)
            }
        } catch {
            return nil
        }
    }

    /** Near 页面的链接（WEB 路由，任何域名）→ 它指向的东西；别的返回 nil（Android `parsePostLink`）。 */
    static func parse(_ url: String) -> PostLink? {
        let raw = url.trimmingCharacters(in: .whitespaces)
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let found = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
            return (1 ..< found.numberOfRanges).compactMap { Range(found.range(at: $0), in: raw).map { String(raw[$0]) } }
        }
        if let groups = match("/panel/discussion/post-detail/([^/?#]+)") { return PostLink(type: .post, id: groups[0]) }
        if let groups = match("/panel/activity-detail/([^/?#]+)/([^/?#]+)") {
            guard let activityType = NearActivityKind.allCases.first(where: { $0.rawValue == groups[0] }) else { return nil }
            return PostLink(type: .activity, id: groups[1], activityType: activityType)
        }
        if let groups = match("/panel/venue-detail/([^/?#]+)") { return PostLink(type: .venue, id: groups[0]) }
        if let groups = match("/panel/building-detail/([^/?#]+)") { return PostLink(type: .building, id: groups[0]) }
        return nil
    }

    /** 链接段落打开的页面。 */
    static func route(_ link: PostLink) -> NearRoute? {
        switch link.type {
        case .post: .post(postId: link.id)
        case .activity: link.activityType.map { .activity(activityType: $0, activityId: link.id) }
        case .venue: .venue(venueId: link.id, sheet: nil)
        case .building: .building(buildingId: link.id)
        }
    }
}

/** 每页一份的链接卡片状态，每个目标只读一次（Android `LinkCards`）。 */
@MainActor
@Observable
final class LinkCards {
    private(set) var states: [String: LinkCardState] = [:]

    func ensure(_ link: PostLink) {
        guard states[link.key] == nil else { return }
        states[link.key] = .loading
        Task {
            let info = await PostLinkLoader.load(link)
            states[link.key] = info.map(LinkCardState.ready) ?? .missing
        }
    }
}

/** 正文里的链接卡片（Android `PostLinkCard`）。 */
struct PostLinkCard: View {
    let link: PostLink
    let state: LinkCardState
    let imageURL: (String?) -> URL?

    var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 56)
            case .missing:
                Label("discussion_link_missing", systemImage: "link.badge.plus").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            case let .ready(info):
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.fill.tertiary)
                    if let url = imageURL(info.coverImageId) { PulsoRemoteImage(url: url) } else { Image(systemName: symbol).foregroundStyle(.secondary) }
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if !info.meta.isEmpty { Text(verbatim: info.meta).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    }

    private var symbol: String { link.type.symbol }
}
