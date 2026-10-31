import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一个找到的人和我跟 TA 的关系（Android `AddFriendRowUi`）。 */
struct AddFriendRowUi: Identifiable {
    let item: LookupProfileItem
    let displayName: String
    let avatarURL: URL?
    let location: String?
    var relation: RelationStatus?

    var id: String { item.profileId }
}

/**
 * 添加好友（Android `AddFriendViewModel`，WEB `AddFriendPage`）：选身份类型 → 提交关键词 → 后端精确匹配
 * 身份 id / 用户名（区分大小写）/ 显示名；每行按 TA 的身份类型走好友 / 关注关系。
 */
@MainActor
@Observable
final class AddFriendModel {
    var scope = ProfileKind.community {
        didSet {
            guard scope != oldValue else { return }
            rows = []
            error = nil
            if let submitted { lookup(submitted) }
        }
    }

    var query = ""
    /** 最近一次提交的关键词；nil 表示还没搜过。 */
    private(set) var submitted: String?
    private(set) var rows: [AddFriendRowUi] = []
    private(set) var isLoading = false
    private(set) var error: UiError?
    private(set) var busyProfileId: String?

    @ObservationIgnored @Injected(\.authQueryStore) private var authQuery
    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var lookupTask: Task<Void, Never>?

    func submit() {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        lookup(keyword)
    }

    private func lookup(_ keyword: String) {
        let kind = scope
        lookupTask?.cancel()
        submitted = keyword
        isLoading = true
        error = nil
        lookupTask = Task {
            do {
                let me = sessionStore.state.value.currentProfileId
                let items = try await authQuery.lookups.get(ProfileLookupKey(kind: kind, keyword: keyword)).filter { $0.profileId != me }
                let relations = try await loadRelations(items)
                guard !Task.isCancelled else { return }
                rows = items.map { row($0, relations[$0.profileId]) }
            } catch {
                guard !Task.isCancelled else { return }
                rows = []
                self.error = UiError(error)
            }
            isLoading = false
        }
    }

    func follow(_ row: AddFriendRowUi) async { await mutate(row) { try await self.socialService.follow(row.item.profileId, row.item.profileScope) } }
    func unfollow(_ row: AddFriendRowUi) async { await mutate(row) { try await self.socialService.unfollow(row.item.profileId, row.item.profileScope) } }

    func sendFriendRequest(_ row: AddFriendRowUi) async {
        await mutate(row) {
            _ = try await self.socialService.sendFriendRequest(SendFriendRequestRequest(targetProfileId: row.item.profileId, targetProfileScope: row.item.profileScope))
        }
    }

    func accept(_ row: AddFriendRowUi) async {
        guard let id = row.relation?.pendingFriendRequest?.friendRequestId else { return }
        await mutate(row) { try await self.socialService.acceptFriendRequest(id) }
    }

    func reject(_ row: AddFriendRowUi) async {
        guard let id = row.relation?.pendingFriendRequest?.friendRequestId else { return }
        await mutate(row) { try await self.socialService.rejectFriendRequest(id) }
    }

    func cancelRequest(_ row: AddFriendRowUi) async {
        guard let id = row.relation?.pendingFriendRequest?.friendRequestId else { return }
        await mutate(row) { try await self.socialService.cancelFriendRequest(id) }
    }

    func unblock(_ row: AddFriendRowUi) async { await mutate(row) { try await self.socialService.unblock(row.item.profileId, row.item.profileScope) } }

    /** 做完再重拉这一屏所有人的关系。 */
    private func mutate(_ row: AddFriendRowUi, _ block: @escaping () async throws -> Void) async {
        guard busyProfileId == nil else { return }
        busyProfileId = row.item.profileId
        defer { busyProfileId = nil }
        do {
            try await block()
            let relations = try await loadRelations(rows.map(\.item))
            for index in rows.indices { rows[index].relation = relations[rows[index].item.profileId] }
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_social_add_friend_action_failed")
        }
    }

    private func loadRelations(_ items: [LookupProfileItem]) async throws -> [String: RelationStatus] {
        guard !items.isEmpty else { return [:] }
        let session = sessionStore.state.value
        let response = try await socialService.getRelations(RelationStatusKey(
            accountId: session.currentAccountId, profileId: session.currentProfileId,
            targets: items.map { SocialTargetProfile(targetProfileId: $0.profileId, targetProfileScope: $0.profileScope) }
        ))
        return Dictionary(response.items.map { ($0.targetProfileId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func row(_ item: LookupProfileItem, _ relation: RelationStatus?) -> AddFriendRowUi {
        let location = [item.city, item.country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        return AddFriendRowUi(
            item: item,
            displayName: item.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? item.citypulsoId,
            avatarURL: ImageURLs.image(item.avatarImageId, base: config.apiBaseURL),
            location: location.isEmpty ? nil : location,
            relation: relation
        )
    }
}

/** 添加好友（Android `AddFriendScreen`）：身份类型分段 + 说明、搜索框、结果行（头像、名字、@用户名、身份 id、角色和地点）和关系按钮。 */
struct AddFriendView: View {
    @State private var model = AddFriendModel()

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            // 身份类型是搜索范围（值筛选，分段）；下面搜索框只认完整的名字、@用户名或身份 id。
            VStack(alignment: .leading, spacing: PulsoSpace.s2) {
                PulsoSegmentedControl(ProfileKind.allCases, selection: $model.scope) { Text(scopeLabel($0)) }
                Text(scopeHint(model.scope)).font(.caption).foregroundStyle(palette.secondaryText)
                HStack(spacing: PulsoSpace.s2) {
                    PulsoSearchField(text: $model.query, prompt: Text("shell_social_add_friend_placeholder"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { model.submit() }
                    Button { model.submit() } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.onAccent)
                            .frame(width: PulsoControlSize.compact.height, height: PulsoControlSize.compact.height)
                            .background(palette.accent.step(9), in: palette.controlShape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("shell_social_add_friend_submit"))
                }
                Text("shell_social_add_friend_exact_hint").font(.caption).foregroundStyle(palette.secondaryText)
            }
            .padding(PulsoSpace.s4)
            List {
                results
            }
        }
        .navigationTitle("shell_social_add_friend_title")
    }

    @ViewBuilder
    private var results: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160).listRowBackground(Color.clear)
        } else if let error = model.error, model.rows.isEmpty {
            PulsoLoadErrorView(error) { model.submit() }.listRowBackground(Color.clear)
        } else if model.submitted == nil {
            Text("shell_social_add_friend_idle").foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center).listRowBackground(Color.clear)
        } else if model.rows.isEmpty {
            PulsoEmptyState(Text("shell_social_add_friend_empty")).frame(minHeight: 300).listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(model.rows) { row in resultRow(row) }
            }
        }
    }

    private func resultRow(_ row: AddFriendRowUi) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: NearRoute.socialProfile(profileId: row.item.profileId)) {
                HStack(alignment: .top, spacing: 14) {
                    PulsoAvatar(url: row.avatarURL, size: 48, fallbackText: row.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(verbatim: "@\(row.item.citypulsoId)").font(.caption).foregroundStyle(.tint).lineLimit(1)
                        Text(verbatim: row.item.profileId).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                chip(ProfileRoleVisuals.kindSymbol(row.item.profileScope), Text(scopeLabel(row.item.profileScope)))
                                ForEach(ProfileRoleVisuals.sorted(row.item.roles), id: \.self) { role in
                                    ProfileRoleLabel(role: role).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.fill.tertiary, in: .capsule)
                                }
                                if let location = row.location { chip("mappin", Text(verbatim: location)) }
                            }
                        }
                    }
                }
            }
            actions(row)
        }
    }

    private func chip(_ symbol: String, _ text: Text) -> some View {
        Label { text } icon: { Image(systemName: symbol) }
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: .capsule)
    }

    @ViewBuilder
    private func actions(_ row: AddFriendRowUi) -> some View {
        let busy = model.busyProfileId == row.item.profileId
        let relation = row.relation
        HStack {
            Spacer()
            if relation?.isBlockedByMe == true {
                Button("shell_social_unblock") { Task { await model.unblock(row) } }.buttonStyle(.pulso(.soft))
            } else {
                if relation?.isFollowing == true {
                    Button("shell_social_unfollow") { Task { await model.unfollow(row) } }.buttonStyle(.pulso(.soft))
                } else {
                    Button("shell_social_follow") { Task { await model.follow(row) } }.buttonStyle(.pulso(.soft))
                }
                if relation?.isFriend == true {
                    Button("shell_social_friends_tag") {}.buttonStyle(.pulso(.soft)).disabled(true)
                } else if relation?.pendingFriendRequest?.direction == .incoming {
                    Button("shell_social_accept") { Task { await model.accept(row) } }.buttonStyle(.pulso())
                    Button("shell_social_reject") { Task { await model.reject(row) } }.buttonStyle(.pulso(.soft))
                } else if relation?.pendingFriendRequest?.direction == .outgoing {
                    Button("shell_social_cancel_request") { Task { await model.cancelRequest(row) } }.buttonStyle(.pulso(.soft))
                } else {
                    Button("shell_social_add_friend") { Task { await model.sendFriendRequest(row) } }.buttonStyle(.pulso())
                }
            }
            if busy { ProgressView() }
        }
        .controlSize(.small)
        .disabled(busy)
    }

    private func scopeLabel(_ kind: ProfileKind) -> LocalizedStringKey {
        switch kind {
        case .community: "shell_social_scope_community"
        case .organization: "shell_social_scope_organization"
        case .authority: "shell_social_scope_authority"
        }
    }

    private func scopeHint(_ kind: ProfileKind) -> LocalizedStringKey {
        switch kind {
        case .community: "shell_social_scope_community_hint"
        case .organization: "shell_social_scope_organization_hint"
        case .authority: "shell_social_scope_authority_hint"
        }
    }
}
