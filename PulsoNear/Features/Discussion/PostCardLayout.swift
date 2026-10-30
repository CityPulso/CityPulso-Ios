import Foundation
import PulsoLinkCore

/** 列表里的帖子共有的字段（`PostCard` 和 `ForumPost`）。 */
protocol PostCardFields {
    var id: String { get }
    var author: DiscussionProfileCard { get }
    var kind: PostKind { get }
    var city: String? { get }
    var title: String { get }
    var contentText: String { get }
    var repostOf: RepostOf? { get }
    var likeCount: Int { get set }
    var commentCount: Int { get }
    var bookmarkCount: Int { get set }
    var repostCount: Int { get }
    var firstPublishedAt: String? { get }
    var previewImageIds: [String] { get }
    var imageCount: Int { get }
    var topics: [PostTopic] { get }
    /** 正文里所有链接，按正文顺序。 */
    var links: [PostLink] { get }
    var forums: [PostForumRef] { get }
    var createdAt: String { get }
    var likedByMe: Bool { get set }
    var bookmarkedByMe: Bool { get set }
}

extension PostCard: PostCardFields, Identifiable {}
extension ForumPost: PostCardFields, Identifiable {}

/** 一组链接先显示几行，其余收在「还有 N 个链接」后面。 */
let postLinkGroupRows = 3

/** 布局显示的格子以外还有几张（最后一格写「+N」）。 */
func hiddenPhotoCount(_ imageCount: Int, shownTiles: Int) -> Int {
    max(0, imageCount - shownTiles)
}

/** 帖子 id 算出的稳定数字（djb2，和 WEB 一样）：同一篇帖子总是同一种样式，一个列表里各种样式混着出现。 */
func postSeed(_ id: String) -> UInt64 {
    var hash: UInt64 = 5381
    for scalar in id.unicodeScalars { hash = ((hash << 5) &+ hash &+ UInt64(scalar.value)) & 0xFFFF_FFFF }
    return hash
}

private func pick<T>(_ seed: UInt64, _ options: [T]) -> T {
    options[Int(seed % UInt64(options.count))]
}

/** 这几种帖子的卡片开头是一个事实框（时间 / 地点 / 名额）和行动按钮。 */
private let factsKinds: Set<PostKind> = [.playersWanted, .match]

/**
 * 信息流卡片画什么（Android `PostCardLayout`）。[linkItems] 是链接区要画的链接（事实框会拿走它的活动）；
 * [factsActivity] 是事实框显示的活动；[question] 让摘要更长、评论读作回答。
 */
struct PostCardLayout: Hashable {
    let style: PostCardStyle
    let photos: PostPhotoLayout
    let links: PostLinkLayout
    let linkItems: [PostLink]
    let facts: Bool
    let factsActivity: PostLink?
    let question: Bool

    /**
     * 按帖子里有什么决定画哪些部分（论坛设计稿）：转发 → 事实框（找球友 / 约球）→ 多个链接（成组）→ 一个链接按类型 →
     * 照片按张数 → 提问 → 纯文字。同一类内容有几种样式时用帖子 id 选，每张卡稳定、列表里有变化。
     */
    init(_ post: some PostCardFields) {
        let seed = postSeed(post.id)
        let photoCount = post.previewImageIds.isEmpty ? 0 : post.imageCount
        let facts = factsKinds.contains(post.kind) && post.repostOf == nil
        let factsActivity = facts ? post.links.first { $0.type == .activity } : nil
        let linkItems = factsActivity.map { activity in post.links.filter { $0 != activity } } ?? post.links
        let question = post.kind == .question
        let only = linkItems.count == 1 ? linkItems.first : nil
        self.linkItems = linkItems
        self.facts = facts
        self.factsActivity = factsActivity
        self.question = question

        // 紧凑：正好一个视觉元素（照片，或一个活动 / 门店链接），缩略图放在文字旁边。
        let sideLink = only.map { $0.type == .activity || $0.type == .venue } ?? false
        let oneVisual = (photoCount > 0 && linkItems.isEmpty) || (photoCount == 0 && sideLink)
        if !facts, post.repostOf == nil, oneVisual, seed % 2 == 1 {
            style = .compact
            if photoCount > 0 {
                photos = photoCount == 1 ? .side : .sideGrid
                links = .none
            } else {
                photos = .none
                links = only?.type == .activity ? .activitySide : .venueSide
            }
            return
        }

        style = .rich
        links = switch true {
        case linkItems.count >= 2: .group
        case only?.type == .activity: photoCount > 0 ? .activityInline : pick(seed, [.activityHero, .activityInline])
        case only?.type == .venue: photoCount > 0 ? .venueRow : .venueHero
        case only != nil: .linked
        default: .none
        }
        photos = switch true {
        case photoCount == 1: .hero
        case photoCount > 1 && (!linkItems.isEmpty || facts): .strip
        case photoCount == 2: .pair
        case photoCount == 3: pick(seed, [.strip, .split])
        case photoCount >= 4: pick(seed, [.mosaic, .strip, .grid])
        default: .none
        }
    }

    /** 文字卡和提问的摘要多给一行。 */
    var longExcerpt: Bool {
        style == .compact || question || (photos == .none && links == .none && !facts)
    }
}

/** 帖子正文下面的照片，按张数：一张宽图、两张并排、一张高的配两张，再往上 2×2 或高图拼。 */
func detailPhotoLayout(postId: String, count: Int) -> PostPhotoLayout {
    switch count {
    case 0: .none
    case 1: .hero
    case 2: .pair
    default: count == 3 || postSeed(postId) % 2 == 0 ? .split : .grid
    }
}

/** 「2026年11月9日 12:00 – 14:00」（设备时区）；同一天才写结束时间。 */
func formatActivityWhen(_ startsAt: String, _ endsAt: String?, locale: Locale = .current) -> String {
    guard let start = DateTimeFormatters.parseInstant(startsAt) else { return "" }
    let head = start.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    guard let end = DateTimeFormatters.parseInstant(endsAt), Calendar.current.isDate(end, inSameDayAs: start) else { return head }
    return "\(head) – \(end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))"
}
