import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 我的资料（对应 Android `ProfileOverviewScreen`）：背景图铺到状态栏下面，可左右滑并自动轮播；
 * 右上角分享 / 编辑 / 身份 / 账号安全。
 */
struct ProfileOverviewView: View {
    @State private var model = ProfileOverviewModel()

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
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: .sectionHeaders) {
                ProfileHero(urls: model.backgroundURLs)
                    .overlay(alignment: .bottomLeading) {
                        identityRow(info).padding(.horizontal).padding(.bottom, 12)
                    }
                details(info).padding(.horizontal)
                ActivityCenterSection(model: model.activity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .refreshable {
            async let profile: Void = model.refresh(showIndicator: true)
            async let activity: Void = model.activity.refresh()
            _ = await (profile, activity)
        }
        .task { await model.observeCounts() }
        .task { await model.activity.observe() }
        .toolbar { toolbar(info) }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    private func identityRow(_ info: CurrentFullAccountInformation) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            Button { model.avatar.open() } label: {
                PulsoAvatar(url: model.avatarURL, size: 84, systemImage: "person", fallbackText: info.displayName)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.tint)
                            .background(.background, in: .circle)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("profile_edit_avatar_hint"))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Group {
                        if let name = info.displayName, !name.isEmpty {
                            Text(verbatim: name)
                        } else {
                            Text("select_profile_unnamed")
                        }
                    }
                    .font(.title2.bold())
                    if let status = model.accountStatusLabel {
                        Text(verbatim: status)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                if let id = info.citypulsoId, !id.isEmpty {
                    Button { model.copyCitypulsoId() } label: {
                        Label {
                            Text(verbatim: "@\(id)")
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("profile_overview_copy_id"))
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: 4)
        }
    }

    private func details(_ info: CurrentFullAccountInformation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                stat("calendar", model.hostedCount, "profile_stat_hosted")
                stat("person.3.fill", model.joinedCount, "profile_stat_joined")
                stat("envelope.fill", info.emails.count, "profile_stat_emails")
                stat("phone.fill", info.phones.count, "profile_stat_phones")
            }
            if let bio = info.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: bio)
            }
            FavoriteSportChips(sports: info.favoriteSports)
            if !model.roles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.roles, id: \.self) { role in
                            ProfileRoleLabel(role: role)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.fill.tertiary, in: .capsule)
                        }
                    }
                }
            }
            metaLine(info)
        }
    }

    private func stat(_ systemImage: String, _ value: Int, _ label: LocalizedStringKey) -> some View {
        Label {
            Text(value, format: .number).bold()
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.tint)
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value, format: .number))
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
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ info: CurrentFullAccountInformation) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: localizedFormat("profile_overview_share_text", info.displayName ?? String(localized: "select_profile_unnamed"))) {
                Label("profile_overview_share", systemImage: "square.and.arrow.up")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink(value: LoopRoute.profileEdit) {
                Label("profile_edit_title", systemImage: "pencil")
            }
            NavigationLink(value: LoopRoute.identities) {
                Label("profile_overview_open_identities", systemImage: "person.text.rectangle")
            }
            NavigationLink(value: LoopRoute.accountSecurity) {
                Label("profile_overview_open_account_security", systemImage: "lock.shield")
            }
        }
    }
}

/** 头图：多张时左右滑并每 4.5 秒自动翻页；没有背景时用主题色渐变。底部压黑渐变方便白字。 */
private struct ProfileHero: View {
    let urls: [URL]
    @State private var page = 0

    var body: some View {
        ZStack {
            if urls.isEmpty {
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        PulsoRemoteImage(url: url).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            }
            LinearGradient(
                stops: [.init(color: .clear, location: 0.18), .init(color: .black.opacity(0.65), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(height: 320)
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
