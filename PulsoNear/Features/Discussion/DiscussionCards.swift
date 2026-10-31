import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 论坛主办方徽标：官方 / 组织 / 球友（Android `ForumBadge`）。 */
struct ForumBadge: View {
    let scope: ProfileKind

    var body: some View {
        Text(scope.forumBadgeKey)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(scope == .authority ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
            .foregroundStyle(scope == .authority ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
}

/** 头像 + 名字（楼主标）+ 时间（Android `AuthorLine`）。 */
struct AuthorLine: View {
    let author: DiscussionProfileCard
    let at: String
    let avatarURL: URL?
    var isOp = false
    var onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            PulsoAvatar(url: avatarURL, size: 32, fallbackText: author.displayName ?? author.profileId)
                .onTapGesture { onOpen?() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(verbatim: author.displayName ?? String(localized: "discussion_unknown_member")).font(.subheadline.weight(.medium)).lineLimit(1)
                    if isOp {
                        Text("discussion_op_tag").font(.caption2.weight(.semibold)).padding(.horizontal, 4).background(Color.accentColor.opacity(0.15), in: .capsule).foregroundStyle(.tint)
                    }
                }
                Text(verbatim: DateTimeFormatters.monthDayTime(at) ?? "").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/** 被转发的帖子（Android `RepostQuote`）。 */
struct RepostQuote: View {
    let repost: RepostOf

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: repost.available
                ? localizedFormat("discussion_repost_of", repost.author.displayName ?? "")
                : String(localized: "discussion_repost_unavailable"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if repost.available {
                Text(verbatim: repost.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let text = repost.contentText, !text.isEmpty { Text(verbatim: text).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 8))
    }
}

/** 图标 + 数字的操作（Android `ActionCount`）。 */
struct ActionCount: View {
    let symbol: String
    let count: Int?
    let label: LocalizedStringKey
    var active = false
    var activeTint: Color = .accentColor
    /** 代替数字的文字（提问帖的「3 个回答」）。 */
    var text: String?
    let action: () -> Void

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if let text {
                    Text(verbatim: text).font(.caption)
                } else if let count, count > 0 {
                    Text(count, format: .number).font(.caption)
                }
            }
            // 平时正文色（Android onSurface），点亮时用 [activeTint]。
            .foregroundStyle(active ? activeTint : palette.text)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/** 帖子下面一排：赞、评论、转发、分享，最右收藏（Android `PostActionBar`）。 */
struct PostActionBar: View {
    let likedByMe: Bool
    let likeCount: Int
    let commentCount: Int
    let repostCount: Int
    let bookmarkedByMe: Bool
    let onLike: () -> Void
    let onComment: () -> Void
    var onRepost: (() -> Void)?
    var shareURL: URL?
    let onBookmark: () -> Void
    /** 提问帖：评论读作回答。 */
    var answers = false

    var body: some View {
        HStack(spacing: 4) {
            ActionCount(symbol: likedByMe ? "heart.fill" : "heart", count: likeCount, label: "discussion_action_like", active: likedByMe, activeTint: .red, action: onLike)
            ActionCount(
                symbol: "bubble.right",
                count: commentCount,
                label: "discussion_action_comment",
                text: answers ? localizedFormat("discussion_card_answers", commentCount) : nil,
                action: onComment
            )
            if let onRepost { ActionCount(symbol: "arrow.2.squarepath", count: repostCount, label: "discussion_action_repost", action: onRepost) }
            if let shareURL {
                ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary).padding(.horizontal, 6) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("discussion_action_share"))
            }
            Spacer()
            ActionCount(symbol: bookmarkedByMe ? "bookmark.fill" : "bookmark", count: nil, label: "discussion_action_bookmark", active: bookmarkedByMe, action: onBookmark)
        }
    }
}

/** 帖子类型标签（Android `PostKindChip`）。 */
struct PostKindChip: View {
    let kind: PostKind

    var body: some View {
        Text(kind.labelKey)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(kind.tone)
            .background(kind.tone.opacity(0.14), in: .capsule)
    }
}

/** 帖子状态（审核中 / 被拒 …）。 */
struct PostStatusChip: View {
    let status: ForumPostStatus

    var body: some View {
        Text(status.labelKey)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(status == .published ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            .background(.fill.tertiary, in: .capsule)
    }
}

/** 帖子的话题「#名字」，点一个打开那个论坛的这个话题。 */
struct TopicChipRow: View {
    let topics: [PostTopic]
    var onOpen: ((PostTopic) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(topics, id: \.id) { topic in
                    Text(verbatim: "#\(topic.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: .capsule)
                        .onTapGesture { onOpen?(topic) }
                }
            }
        }
    }
}

/** 论坛的活动类型标签（带活动类型图），有 [max] 时多的合成「+N」（Android `ForumTypeTags`）。 */
struct ForumTypeTags: View {
    let types: [ForumActivityType]
    var max: Int?

    var body: some View {
        let shown = max.map { Array(types.prefix($0)) } ?? types
        HStack(spacing: 4) {
            ForEach(shown, id: \.self) { type in
                HStack(spacing: 2) {
                    if let activityType = type.activityType {
                        Image(activityType.iconAsset).resizable().frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "square.grid.2x2").font(.caption2)
                    }
                    Text(type.labelKey).font(.caption2).lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.fill.tertiary, in: .capsule)
            }
            if types.count > shown.count {
                Text(verbatim: localizedFormat("discussion_forum_types_more", types.count - shown.count)).font(.caption2)
                    .padding(.horizontal, 6).background(.fill.tertiary, in: .capsule)
            }
        }
    }
}

/**
 * 信息流里的帖子（Android `PostCardItem`，论坛设计稿）。头部：头像、「名字 · 在某论坛 +N」、「时间 · 城市」、类型、⋯。
 * 正文按帖子里有什么来画（见 [PostCardLayout]）：几种照片布局、关联的活动 / 门店 / 帖子各自一张卡、多个链接成组、
 * 找球友 / 约球的事实框，或者文字旁边一张缩略图的紧凑卡。话题、被转发的原帖和操作排在最后。
 * 链接目标在卡片出现时经页面的 [LinkCards] 读取。
 */
struct PostCardView<Post: PostCardFields>: View {
    let post: Post
    let imageURL: (String?) -> URL?
    let onOpen: () -> Void
    let onLike: () -> Void
    let onBookmark: () -> Void
    var onRepost: (() -> Void)?
    var onOpenForum: ((String) -> Void)?
    var onOpenAuthor: (() -> Void)?
    var onOpenTopic: ((PostTopic) -> Void)?
    var status: ForumPostStatus?
    var pinned = false
    var reason: String?
    var hideForums = false
    var onReport: (() -> Void)?

    @Environment(LinkCards.self) private var sharedCards: LinkCards?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @State private var ownCards = LinkCards()

    private var cards: LinkCards { sharedCards ?? ownCards }

    var body: some View {
        let layout = PostCardLayout(post)
        VStack(alignment: .leading, spacing: 12) {
            header
            if layout.style == .compact {
                HStack(alignment: .top, spacing: 12) {
                    text(layout, compact: true).frame(maxWidth: .infinity, alignment: .leading)
                    if layout.photos != .none {
                        PostPhotos(layout: layout.photos, previewIds: post.previewImageIds, imageCount: post.imageCount, imageURL: imageURL)
                    } else if let side = layout.linkItems.first {
                        LinkTargetCard(link: side, state: state(side), variant: .side, imageURL: imageURL, onOpen: { open(side) })
                    }
                }
            } else {
                text(layout, compact: false)
                if layout.facts {
                    PostFactsBox(
                        activity: layout.factsActivity.map(state),
                        city: post.city,
                        onJoin: { if let activity = layout.factsActivity { open(activity) } },
                        onInterested: onOpen
                    )
                }
                // 关联帖子读作背景，放在照片前面；活动 / 门店卡跟在照片后面。
                if layout.links == .linked { linkArea(layout) }
                PostPhotos(layout: layout.photos, previewIds: post.previewImageIds, imageCount: post.imageCount, imageURL: imageURL)
                if layout.links != .linked { linkArea(layout) }
            }
            if !post.topics.isEmpty { TopicChipRow(topics: post.topics, onOpen: onOpenTopic) }
            if let repost = post.repostOf { RepostQuote(repost: repost) }
            if let reason, !reason.isEmpty { Text(verbatim: reason).font(.caption).foregroundStyle(.red) }
            PostActionBar(
                likedByMe: post.likedByMe, likeCount: post.likeCount, commentCount: post.commentCount, repostCount: post.repostCount,
                bookmarkedByMe: post.bookmarkedByMe, onLike: onLike, onComment: onOpen, onRepost: onRepost, shareURL: postShareURL(post.id), onBookmark: onBookmark,
                answers: layout.question
            )
        }
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .onAppear {
            for link in (layout.factsActivity.map { [$0] } ?? []) + layout.linkItems where layout.links != .group || link == layout.factsActivity {
                cards.ensure(link)
            }
        }
    }

    /** 头像、「名字 · 在某论坛 +N」、「时间 · 城市」，然后置顶、状态、类型和菜单。 */
    private var header: some View {
        HStack(spacing: 10) {
            PulsoAvatar(url: imageURL(post.author.avatarImageId), size: 40, fallbackText: post.author.displayName ?? post.author.profileId)
                .onTapGesture { onOpenAuthor?() }
            VStack(alignment: .leading, spacing: 1) {
                let first = hideForums ? nil : post.forums.first
                HStack(spacing: 4) {
                    Text(verbatim: post.author.displayName ?? String(localized: "discussion_unknown_member")).font(.subheadline.bold()).lineLimit(1)
                    if let first {
                        Text(verbatim: localizedFormat("discussion_card_in_forum", first.forumName) + (post.forums.count > 1 ? " +\(post.forums.count - 1)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .onTapGesture { onOpenForum?(first.forumId) }
                    }
                }
                let meta = [DateTimeFormatters.monthDayTime(post.firstPublishedAt ?? post.createdAt), post.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty { Text(verbatim: meta).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint).accessibilityLabel(Text("discussion_pinned")) }
            if let status, status != .published { PostStatusChip(status: status) }
            PostKindChip(kind: post.kind)
            if let onReport {
                Menu {
                    Button(action: onReport) { Label("discussion_action_report", systemImage: "flag") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .accessibilityLabel(Text("discussion_more_actions"))
            }
        }
    }

    private func text(_ layout: PostCardLayout, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: post.title).font((compact ? Font.headline : .title3).bold()).lineLimit(2)
            if !post.contentText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: post.contentText).font(.subheadline).foregroundStyle(.secondary).lineLimit(layout.longExcerpt ? 3 : 2)
            }
        }
    }

    /** 丰富卡的链接区：一组行、大的或内嵌的活动卡、大的门店卡或门店条，或者一行。 */
    @ViewBuilder
    private func linkArea(_ layout: PostCardLayout) -> some View {
        if let only = layout.linkItems.first {
            switch layout.links {
            case .none, .activitySide, .venueSide:
                EmptyView()
            case .group:
                PostLinkGroup(links: layout.linkItems, cards: cards, imageURL: imageURL, onOpen: { open($0) })
            case .activityHero, .venueHero:
                LinkTargetCard(link: only, state: state(only), variant: .hero, imageURL: imageURL, onOpen: { open(only) })
            case .activityInline:
                LinkTargetCard(link: only, state: state(only), variant: .inline, imageURL: imageURL, onOpen: { open(only) })
            case .venueRow:
                LinkTargetCard(link: only, state: state(only), variant: .bar, imageURL: imageURL, onOpen: { open(only) })
            case .linked:
                LinkTargetCard(
                    link: only, state: state(only), variant: .row, imageURL: imageURL, onOpen: { open(only) },
                    label: only.type == .post ? String(localized: "discussion_card_linked_post") : nil
                )
            }
        }
    }

    private func state(_ link: PostLink) -> LinkCardState {
        cards.states[link.key] ?? .loading
    }

    private func open(_ link: PostLink) {
        if let route = PostLinkLoader.route(link) { shell?.push(route) }
    }
}

/** 一页共用一份链接卡片缓存（Android `PostLinksViewModel` 每页一个）：页面里所有帖子卡片从这里读链接目标。 */
private struct PostLinkCardsScope: ViewModifier {
    @State private var cards = LinkCards()

    func body(content: Content) -> some View {
        content.environment(cards)
    }
}

extension View {
    /** 给这一页的帖子卡片一份共用的链接卡片缓存。 */
    func postLinkCards() -> some View {
        modifier(PostLinkCardsScope())
    }
}

/** 论坛的一行（Android `ForumRow`）：封面上叠头像，名字和徽标，活动类型，简介，收藏 / 帖子数，右边收藏星。 */
struct ForumRowView: View {
    let name: String
    let ownerScope: ProfileKind
    let activityTypes: [ForumActivityType]
    let description: String
    let favoriteCount: Int
    let postCount: Int
    let avatarURL: URL?
    let coverURL: URL?
    var favorited: Bool?
    var busy = false
    var onToggleFollow: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(.fill.tertiary)
                if let coverURL { PulsoRemoteImage(url: coverURL) }
                PulsoRemoteImage(url: avatarURL)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.4))
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.systemBackground), lineWidth: 2))
                    .padding(4)
            }
            .frame(width: 96, height: 64)
            .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(verbatim: name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    ForumBadge(scope: ownerScope)
                }
                if !activityTypes.isEmpty { ForumTypeTags(types: activityTypes, max: 3) }
                if !description.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(verbatim: description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(verbatim: localizedFormat("discussion_forum_counts", favoriteCount, postCount)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let favorited, let onToggleFollow {
                Button(action: onToggleFollow) {
                    Image(systemName: favorited ? "star.fill" : "star").foregroundStyle(favorited ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .disabled(busy)
                .accessibilityLabel(Text((favorited ? "discussion_unfollow" : "discussion_follow") as LocalizedStringKey))
            }
        }
    }
}

extension ForumRowView {
    init(forum: ForumItem, imageURL: (String?) -> URL?, busy: Bool = false, onToggleFollow: (() -> Void)?) {
        self.init(
            name: forum.name, ownerScope: forum.owner.profileScope, activityTypes: forum.activityTypes, description: forum.description,
            favoriteCount: forum.favoriteCount, postCount: forum.postCount, avatarURL: imageURL(forum.avatarImageId), coverURL: imageURL(forum.coverImageId),
            favorited: forum.favoritedByMe, busy: busy, onToggleFollow: onToggleFollow
        )
    }
}

/** 一条评论（Android `CommentRow`）：作者（楼主标）、引用的那条、正文、赞 / 收藏 / 回复 / 举报 / 删除。 */
struct CommentRowView: View {
    let comment: PostComment
    let avatarURL: URL?
    let onLike: () -> Void
    let onBookmark: () -> Void
    var onReply: (() -> Void)?
    var onReport: (() -> Void)?
    var onDelete: (() -> Void)?
    var onOpenAuthor: (() -> Void)?
    /** 显示它回复的那条；回复顶层评论的不用。 */
    var showQuote = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuthorLine(author: comment.author, at: comment.createdAt, avatarURL: avatarURL, isOp: comment.isOp, onOpen: onOpenAuthor)
            if showQuote, let reply = comment.replyTo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: reply.available ? localizedFormat("discussion_reply_to", reply.author.displayName ?? "") : String(localized: "discussion_reply_unavailable"))
                        .font(.caption2).foregroundStyle(.secondary)
                    if reply.available { Text(verbatim: reply.excerpt).font(.caption).lineLimit(2) }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary, in: .rect(cornerRadius: 6))
            }
            RichTextBody(html: comment.contentHtml)
            HStack(spacing: 4) {
                ActionCount(symbol: comment.likedByMe ? "heart.fill" : "heart", count: comment.likeCount, label: "discussion_action_like", active: comment.likedByMe, activeTint: .red, action: onLike)
                ActionCount(symbol: comment.bookmarkedByMe ? "bookmark.fill" : "bookmark", count: comment.bookmarkCount, label: "discussion_action_bookmark", active: comment.bookmarkedByMe, action: onBookmark)
                if let onReply { Button("discussion_action_reply", action: onReply).font(.caption).buttonStyle(.borderless).foregroundStyle(.secondary) }
                if let onReport { Button("discussion_action_report", action: onReport).font(.caption).buttonStyle(.borderless).foregroundStyle(.secondary) }
                if let onDelete { Button("discussion_action_delete", role: .destructive, action: onDelete).font(.caption).buttonStyle(.borderless) }
            }
        }
        .padding(.vertical, 4)
    }
}
