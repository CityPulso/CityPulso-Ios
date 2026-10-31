import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 我的资料（对应 Android `ProfileOverviewScreen` + `ProfileHeaderBlock`）：背景图铺满整个头部（可左右滑、自动轮播），
 * 头像、名字、统计、简介、喜欢的运动压在黑渐变上用白字，底部渐变到页面底色接活动中心。
 * 顶部一行封面按钮：被推进来时左边返回，右边分享 / 编辑 / 账号安全（身份从编辑资料页进）。
 */
struct ProfileOverviewView: View {
    @State private var model = ProfileOverviewModel()
    @State private var pickingFavorites = false
    @State private var creatorTip = false
    @Environment(\.pulsoPalette) private var palette
    @Environment(\.isPresented) private var isPushed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let info = model.info {
                content(info)
            } else if let error = model.loadError {
                PulsoLoadErrorView(error) { Task { await model.refresh(showIndicator: true) } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.observe() }
        .task { await model.refresh(showIndicator: false) }
        .avatarUploadSheet(model.avatar)
    }

    private func content(_ info: CurrentFullAccountInformation) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                header(info)
                ActivityCenterSection(model: model.activity)
            }
        }
        .overlay(alignment: .top) { topActions(info) }
        .refreshable {
            async let profile: Void = model.refresh(showIndicator: true)
            async let activity: Void = model.activity.refresh()
            _ = await (profile, activity)
        }
        .task { await model.observeCounts() }
        .task { await model.observeRelationCounts() }
        .sheet(isPresented: $pickingFavorites) {
            FavoritesPickerSheet(initial: info.favoriteSports) { next in
                pickingFavorites = false
                Task { await model.saveFavoriteSports(next) }
            }
        }
        .task { await model.activity.observe() }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    /** 头部：背景图 + 黑渐变 + 底部渐变到页面底色，上面一列白字内容（左右 24，项间 16）。 */
    private func header(_ info: CurrentFullAccountInformation) -> some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s4) {
            identityRow(info)
            stats
            if let bio = info.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: bio)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
            }
            favorites(info)
            metaLine(info)
        }
        .padding(.horizontal, PulsoSpace.s5)
        .padding(.top, PulsoSpace.s1)
        .padding(.bottom, PulsoSpace.s2)
        // 顶部按钮行留出来（按钮行浮在内容上面、不随滚动）。
        .padding(.top, PulsoControlSize.small.height + PulsoSpace.s2)
        .background {
            ZStack(alignment: .bottom) {
                ProfileHero(urls: model.backgroundURLs)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.18), location: 0.18),
                        .init(color: .black.opacity(0.72), location: 0.72),
                        .init(color: .black.opacity(0.28), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(colors: [.clear, palette.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
            }
            // 背景图往上铺到状态栏下面：滚动内容从安全区下面开始，背景往上多画一截（滚动视图不裁安全区）。
            .padding(.top, -120)
            .allowsHitTesting(false)
        }
    }

    /** 顶部按钮行（固定不随内容滚）：被推进来时左边返回，右边分享 / 编辑资料 / 账号安全。 */
    private func topActions(_ info: CurrentFullAccountInformation) -> some View {
        HStack(spacing: PulsoSpace.s1) {
            if isPushed {
                PulsoIconButton("arrow.left", label: Text("profile_back")) { dismiss() }
            }
            Spacer()
            ShareLink(item: localizedFormat("profile_overview_share_text", info.displayName ?? String(localized: "select_profile_unnamed"))) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: PulsoControlSize.small.height, height: PulsoControlSize.small.height)
                    .background(.black.opacity(0.36), in: palette.controlShape)
            }
            .accessibilityLabel(Text("profile_overview_share"))
            NavigationLink(value: LoopRoute.profileEdit) {
                overlayIcon("pencil")
            }
            .accessibilityLabel(Text("profile_edit_title"))
            NavigationLink(value: LoopRoute.accountSecurity) {
                overlayIcon("lock.shield")
            }
            .accessibilityLabel(Text("profile_overview_open_account_security"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PulsoSpace.s2)
        .padding(.vertical, PulsoSpace.s1)
    }

    private func overlayIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: PulsoControlSize.small.height, height: PulsoControlSize.small.height)
            .background(.black.opacity(0.36), in: palette.controlShape)
    }

    /** 头像（80，角上实心铅笔）+ 名字 / 状态 / 创作者星 + @ID 复制。 */
    private func identityRow(_ info: CurrentFullAccountInformation) -> some View {
        HStack(spacing: PulsoSpace.s4) {
            Button { model.avatar.open() } label: {
                PulsoAvatar(url: model.avatarURL, size: 80, systemImage: "person", fallbackText: info.displayName)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                PulsoIconButton("pencil", label: Text("profile_edit_avatar_hint"), variant: .solid, size: 26, iconSize: 13) {
                    model.avatar.open()
                }
            }

            VStack(alignment: .leading, spacing: PulsoSpace.half) {
                HStack(spacing: PulsoSpace.s2) {
                    Group {
                        if let name = info.displayName, !name.isEmpty {
                            Text(verbatim: name)
                        } else {
                            Text("select_profile_unnamed")
                        }
                    }
                    .font(.title2.bold())
                    .lineLimit(1)
                    if let status = model.accountStatusLabel {
                        Text(verbatim: status)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, PulsoSpace.s2)
                            .padding(.vertical, PulsoSpace.half)
                            .background(.black.opacity(0.42), in: palette.chipShape)
                    }
                    if model.isCreator {
                        Button { creatorTip = true } label: {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .padding(PulsoSpace.half + 1)
                                .background(.black.opacity(0.42), in: palette.chipShape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("profile_role_creator"))
                        .popover(isPresented: $creatorTip) {
                            Text("profile_role_creator").font(.footnote).padding(.horizontal, 12).padding(.vertical, 8)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                if let id = info.citypulsoId, !id.isEmpty {
                    Button { model.copyCitypulsoId() } label: {
                        HStack(spacing: PulsoSpace.s1) {
                            Text(verbatim: "@\(id)").lineLimit(1)
                            Image(systemName: "doc.on.doc")
                        }
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("profile_overview_copy_id"))
                }
            }
            .foregroundStyle(.white)
        }
    }

    /** 关注 / 粉丝 / 活动：白色粗数字 + 名称；关注和粉丝点开社交的对应标签，活动不能点。 */
    private var stats: some View {
        HStack(spacing: PulsoSpace.s5) {
            NavigationLink(value: LoopRoute.social(tab: .following)) { stat(model.followingCount, "profile_stat_following") }
                .buttonStyle(.plain)
            NavigationLink(value: LoopRoute.social(tab: .followers)) { stat(model.followerCount, "profile_stat_followers") }
                .buttonStyle(.plain)
            stat(model.activityCount, "profile_stat_activities")
        }
    }

    /** 喜欢的运动一行（点开选择面板）；还没选时是一个「添加」小标签。 */
    @ViewBuilder
    private func favorites(_ info: CurrentFullAccountInformation) -> some View {
        if info.favoriteSports.isEmpty {
            Button { pickingFavorites = true } label: {
                Label("profile_favorite_sports_add", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, PulsoSpace.s3)
                    .padding(.vertical, PulsoSpace.s1)
                    .background(.black.opacity(0.42), in: palette.chipShape)
            }
            .buttonStyle(.plain)
        } else {
            FavoriteSportChips(sports: info.favoriteSports)
                .contentShape(.rect)
                .onTapGesture { pickingFavorites = true }
                .accessibilityAddTraits(.isButton)
        }
    }

    /** 还没回来的数字显示 `-`，不显示 0。 */
    private func stat(_ value: Int?, _ label: LocalizedStringKey) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: PulsoSpace.s1) {
            Group {
                if let value { Text(value, format: .number) } else { Text(verbatim: "-") }
            }
            .font(.headline.bold())
            .foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.82))
        }
        .accessibilityElement(children: .combine)
    }

    /** `全名 | 生日 | 性别 | 城市 | 网站`，只显示填了的部分；网站可以点开。 */
    @ViewBuilder
    private func metaLine(_ info: CurrentFullAccountInformation) -> some View {
        let gender: Text? = info.gender.flatMap { raw in
            raw.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                : GenderOption.preset(raw).map { Text($0.labelKey) } ?? Text(verbatim: raw)
        }
        let parts: [Text] = [info.fullName.map { Text(verbatim: $0) }, Birthday.display(info.birthday).map { Text(verbatim: $0) }, gender, model.location.map { Text(verbatim: $0) }].compactMap { $0 }
        let website = info.website.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        if !parts.isEmpty || website != nil {
            // 一整段 Text 拼起来，自然换行；网站部分是 Markdown 链接，可以点开。
            let separator = Text(verbatim: " | ")
            let joined = parts.enumerated().reduce(Text(verbatim: "")) { line, item in
                item.offset == 0 ? item.element : Text("\(line)\(separator)\(item.element)")
            }
            let link: Text? = website.map { site in
                if let url = normalizedWebsiteURL(site) {
                    Text(AttributedString(site, attributes: AttributeContainer().link(url).underlineStyle(.single)))
                } else {
                    Text(verbatim: site)
                }
            }
            Group {
                if let link {
                    parts.isEmpty ? link : Text("\(joined)\(separator)\(link)")
                } else {
                    joined
                }
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
            .tint(palette.accent.step(9))
            .lineLimit(2)
        }
    }
}

/** 头图：多张时每 4.5 秒自动翻页；没有背景时用强调色 step8 → step5 渐变。铺满给它的区域。 */
private struct ProfileHero: View {
    let urls: [URL]
    @State private var page = 0
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ZStack {
            if urls.isEmpty {
                LinearGradient(colors: [palette.accent.step(8), palette.accent.step(5)], startPoint: .top, endPoint: .bottom)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        PulsoRemoteImage(url: url).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            }
        }
        .clipped()
        .task(id: urls.count) {
            guard urls.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.5))
                withAnimation { page = (page + 1) % urls.count }
            }
        }
    }
}

/** 资料页的喜欢的运动：本地选好，点完成才保存；下滑关掉保留原来的（Android `FavoriteSportsSheet`）。 */
private struct FavoritesPickerSheet: View {
    let onDone: ([FavoriteSport]) -> Void
    @State private var picked: [FavoriteSport]

    init(initial: [FavoriteSport], onDone: @escaping ([FavoriteSport]) -> Void) {
        self.onDone = onDone
        _picked = State(initialValue: initial)
    }

    var body: some View {
        FavoriteSportPicker(selected: $picked) { onDone(picked) }
    }
}
