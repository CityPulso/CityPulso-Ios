import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 群里的一个人（Android `GroupMemberRowUi`）。 */
struct GroupMemberRowUi: Identifiable, Hashable {
    let profileId: String
    let profileScope: ProfileKind
    let displayName: String
    let avatarURL: URL?
    let role: ConversationRole
    let isSelf: Bool

    var id: String { profileId }
}

/** 群成员列表（Android `GroupMembersSource`），成员页和加人页共用；昵称头像来自资料卡缓存，一次批量拉。 */
@MainActor
enum GroupMembersSource {
    private static let memberLimit = 100

    static func memberIds(_ conversationId: String) async throws -> Set<String> {
        try await Set(Container.shared.communicationService().listGroupMembers(conversationId, limit: memberLimit).items.map(\.profileId))
    }

    static func members(_ conversationId: String) async throws -> [GroupMemberRowUi] {
        let container = Container.shared
        let members = try await container.communicationService().listGroupMembers(conversationId, limit: memberLimit).items
        let ids = members.map(\.profileId)
        let auth = container.authService()
        try? await auth.ensureProfileCards(ids)
        var cards: [String: ProfileCard] = [:]
        for await value in auth.observeProfileCards(ids) {
            cards = value
            break
        }
        let me = container.authSessionStore().state.value.currentProfileId
        let base = container.pulsoCoreConfig().apiBaseURL
        return members.map { member in
            let card = cards[member.profileId]
            return GroupMemberRowUi(
                profileId: member.profileId,
                profileScope: member.profileScope,
                displayName: card?.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(member.profileId.prefix(8)),
                avatarURL: ImageURLs.image(card?.avatarImageId, base: base),
                role: member.role,
                isSelf: member.profileId == me
            )
        }
    }
}

extension ConversationRole {
    var labelKey: LocalizedStringKey {
        switch self {
        case .owner: "chat_settings_role_owner"
        case .admin: "chat_settings_role_admin"
        case .member: "chat_settings_role_member"
        }
    }
}

/** 群成员（Android `GroupMembersViewModel`）：成员变了重拉；移除别人要按住确认。 */
@MainActor
@Observable
final class GroupMembersModel {
    let conversationId: String
    private(set) var members = Loadable<[GroupMemberRowUi]>()
    private(set) var removingProfileId: String?

    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.communicationEventBus) private var bus

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    func observe() async {
        // 先订阅再拉：拉的过程中来的失效不会丢。
        let pulses = bus.signals(where: { $0 == .invalidateGroupMembers })
        await refresh()
        for await _ in pulses {
            await refresh()
        }
    }

    func refresh() async {
        do {
            members = try await Loadable(data: GroupMembersSource.members(conversationId), isLoading: false)
        } catch {
            members = Loadable(data: members.data, isLoading: false, error: UiError(error))
        }
    }

    func remove(_ row: GroupMemberRowUi) async {
        guard removingProfileId == nil else { return }
        removingProfileId = row.profileId
        defer { removingProfileId = nil }
        do {
            try await communicationService.removeGroupMember(conversationId, profileId: row.profileId, profileScope: row.profileScope)
            members.data?.removeAll { $0.profileId == row.profileId }
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_remove_failed")
        }
    }
}

struct GroupMembersView: View {
    @State private var model: GroupMembersModel
    @State private var removing: GroupMemberRowUi?

    init(conversationId: String) {
        _model = State(initialValue: GroupMembersModel(conversationId: conversationId))
    }

    var body: some View {
        Group {
            if let members = model.members.data {
                if members.isEmpty {
                    ContentUnavailableView("chat_settings_members_empty", systemImage: "person.3")
                } else {
                    List(members) { row in
                        HStack(spacing: 12) {
                            NavigationLink(value: NearRoute.socialProfile(profileId: row.profileId)) {
                                HStack(spacing: 12) {
                                    PulsoAvatar(url: row.avatarURL, size: 40, fallbackText: row.displayName)
                                    VStack(alignment: .leading) {
                                        Text(verbatim: row.displayName).font(.subheadline.weight(.semibold))
                                        Text(row.role.labelKey).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !row.isSelf {
                                Button("chat_settings_remove") { removing = row }
                                    .buttonStyle(.pulso(.soft))
                                    .disabled(model.removingProfileId != nil)
                            }
                        }
                    }
                }
            } else if let error = model.members.error {
                PulsoLoadErrorView(error) { Task { await model.refresh() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("chat_settings_members")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NearRoute.groupAddMembers(conversationId: model.conversationId)) {
                    Label("chat_settings_add_members", systemImage: "person.badge.plus")
                }
            }
        }
        .task { await model.observe() }
        .sheet(item: $removing) { row in
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: localizedFormat("chat_settings_remove_title", row.displayName)).font(.title3.bold())
                Text("chat_settings_remove_body").foregroundStyle(.secondary)
                PulsoHoldButton("chat_settings_remove", loading: model.removingProfileId == row.profileId) {
                    Task {
                        await model.remove(row)
                        removing = nil
                    }
                }
            }
            .padding(24)
            .presentationDetents([.height(240)])
        }
    }
}

/** 把好友加进群（Android `GroupAddMembersViewModel`）：只列还不在群里的好友，多选后一次加。 */
@MainActor
@Observable
final class GroupAddMembersModel {
    let conversationId: String
    private(set) var candidates = Loadable<[FriendItem]>()
    private(set) var selectedIds: Set<String> = []
    private(set) var isSubmitting = false

    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.communicationService) private var communicationService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    func avatarURL(_ item: FriendItem) -> URL? { ImageURLs.image(item.profile.avatarImageId, base: config.apiBaseURL) }

    func displayName(_ item: FriendItem) -> String {
        item.profile.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(item.friendProfileId.prefix(8))
    }

    func load() async {
        do {
            let memberIds = try await GroupMembersSource.memberIds(conversationId)
            let session = sessionStore.state.value
            let friends = try await socialService.getFriends(FriendsKey(accountId: session.currentAccountId, profileId: session.currentProfileId))
            candidates = Loadable(data: friends.filter { !memberIds.contains($0.friendProfileId) }, isLoading: false)
        } catch {
            candidates = Loadable(data: candidates.data, isLoading: false, error: UiError(error))
        }
    }

    func toggle(_ profileId: String) {
        if selectedIds.contains(profileId) { selectedIds.remove(profileId) } else { selectedIds.insert(profileId) }
    }

    func submit() async -> Bool {
        guard !selectedIds.isEmpty, !isSubmitting else { return false }
        isSubmitting = true
        do {
            _ = try await communicationService.addGroupMembers(conversationId, AddMembersRequest(members: selectedIds.map { ConversationMemberRef(profileId: $0, profileScope: .community) }))
            return true
        } catch {
            isSubmitting = false
            PulsoMessageCenter.shared.error(error, fallback: "chat_settings_add_failed")
            return false
        }
    }
}

struct GroupAddMembersView: View {
    @State private var model: GroupAddMembersModel
    @Environment(\.dismiss) private var dismiss

    init(conversationId: String) {
        _model = State(initialValue: GroupAddMembersModel(conversationId: conversationId))
    }

    var body: some View {
        Group {
            if let candidates = model.candidates.data {
                if candidates.isEmpty {
                    ContentUnavailableView("chat_settings_add_members_empty", systemImage: "person.2", description: Text("chat_settings_add_members_empty_hint"))
                } else {
                    List(candidates, id: \.friendProfileId) { friend in
                        let selected = model.selectedIds.contains(friend.friendProfileId)
                        Button { model.toggle(friend.friendProfileId) } label: {
                            HStack(spacing: 12) {
                                PulsoAvatar(url: model.avatarURL(friend), size: 40, fallbackText: model.displayName(friend))
                                Text(verbatim: model.displayName(friend))
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } else if let error = model.candidates.error {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("chat_settings_add_members")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("chat_settings_add") { Task { if await model.submit() { dismiss() } } }
                    .disabled(model.selectedIds.isEmpty || model.isSubmitting)
            }
        }
        .task { await model.load() }
    }
}
