import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 隐私设置（对应 Android `PrivacySettingsScreen`）。 */
struct PrivacySettingsView: View {
    private static let directMessageOrder: [SocialDirectMessagePolicy] = [.strangers, .friends, .peopleFollowedByMe, .peopleFollowingMe]
    private static let groupInviteOrder: [SocialGroupInvitePolicy] = [.strangers, .friends, .peopleFollowedByMe, .peopleFollowingMe]

    @State private var model = PrivacySettingsModel()

    var body: some View {
        content
            .navigationTitle("shell_privacy_title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("shell_privacy_save") {
                        Task { await model.save() }
                    }
                    .disabled(!model.isDirty || model.saving)
                }
            }
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let settings = model.draft {
            Form {
                Section("shell_privacy_friend_request_title") {
                    Picker(selection: Binding(get: { settings.friendRequestPolicy }, set: { value in model.edit { $0.friendRequestPolicy = value } })) {
                        Text("shell_privacy_policy_everyone").tag(SocialFriendRequestPolicy.everyone)
                        Text("shell_privacy_policy_people_followed").tag(SocialFriendRequestPolicy.peopleFollowedByMe)
                        Text("shell_privacy_policy_mutual_follows").tag(SocialFriendRequestPolicy.mutualFollows)
                        Text("shell_privacy_policy_nobody").tag(SocialFriendRequestPolicy.nobody)
                    } label: {
                        Text("shell_privacy_friend_request_title")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    ForEach(Self.directMessageOrder, id: \.self) { audience in
                        Toggle(audience.labelKey, isOn: Binding(
                            get: { settings.directMessagePolicy.contains(audience) },
                            set: { _ in model.edit { $0.directMessagePolicy = toggled($0.directMessagePolicy, audience, order: Self.directMessageOrder) } }
                        ))
                    }
                } header: {
                    Text("shell_privacy_direct_message_title")
                } footer: {
                    if settings.directMessagePolicy.isEmpty { Text("shell_privacy_nobody_hint") }
                }

                Section {
                    ForEach(Self.groupInviteOrder, id: \.self) { audience in
                        Toggle(audience.labelKey, isOn: Binding(
                            get: { settings.groupInvitePolicy.contains(audience) },
                            set: { _ in model.edit { $0.groupInvitePolicy = toggled($0.groupInvitePolicy, audience, order: Self.groupInviteOrder) } }
                        ))
                    }
                } header: {
                    Text("shell_privacy_group_invite_title")
                } footer: {
                    if settings.groupInvitePolicy.isEmpty { Text("shell_privacy_nobody_hint") }
                }

                Section("shell_privacy_visibility_title") {
                    Toggle("shell_privacy_show_friend_list", isOn: Binding(get: { settings.showFriendList }, set: { value in model.edit { $0.showFriendList = value } }))
                    Toggle("shell_privacy_show_following_list", isOn: Binding(get: { settings.showFollowingList }, set: { value in model.edit { $0.showFollowingList = value } }))
                    Toggle("shell_privacy_show_follower_list", isOn: Binding(get: { settings.showFollowerList }, set: { value in model.edit { $0.showFollowerList = value } }))
                    Toggle("shell_privacy_show_block_list", isOn: Binding(get: { settings.showBlockList }, set: { value in model.edit { $0.showBlockList = value } }))
                }
            }
        } else if let error = model.loadError {
            PulsoLoadErrorView(error) { Task { await model.load() } }
        } else {
            ProgressView()
        }
    }
}

extension SocialDirectMessagePolicy {
    fileprivate var labelKey: LocalizedStringKey {
        switch self {
        case .strangers: "shell_privacy_policy_strangers"
        case .friends: "shell_privacy_policy_friends"
        case .peopleFollowedByMe: "shell_privacy_policy_people_followed"
        case .peopleFollowingMe: "shell_privacy_policy_people_following"
        }
    }
}

extension SocialGroupInvitePolicy {
    fileprivate var labelKey: LocalizedStringKey {
        switch self {
        case .strangers: "shell_privacy_policy_strangers"
        case .friends: "shell_privacy_policy_friends"
        case .peopleFollowedByMe: "shell_privacy_policy_people_followed"
        case .peopleFollowingMe: "shell_privacy_policy_people_following"
        }
    }
}
