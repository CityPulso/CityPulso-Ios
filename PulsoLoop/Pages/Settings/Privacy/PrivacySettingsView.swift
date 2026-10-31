import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 隐私设置（对应 Android `PrivacySettingsScreen`）。 */
struct PrivacySettingsView: View {
    private static let directMessageOrder: [SocialDirectMessagePolicy] = [.strangers, .friends, .peopleFollowedByMe, .peopleFollowingMe]
    private static let groupInviteOrder: [SocialGroupInvitePolicy] = [.strangers, .friends, .peopleFollowedByMe, .peopleFollowingMe]

    @State private var model = PrivacySettingsModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        content
            .navigationTitle("shell_privacy_title")
            // 改了才出底栏的保存（Android bottomBar 的 PulsoSubmitButton）。
            .safeAreaInset(edge: .bottom) {
                if model.isDirty || model.saving {
                    Button {
                        Task { await model.save() }
                    } label: {
                        PulsoButtonLabel("shell_privacy_save", loading: model.saving)
                    }
                    .buttonStyle(.pulso(fullWidth: true))
                    .disabled(model.saving)
                    .padding(PulsoSpace.s4)
                    .background(palette.background.shadow(.drop(color: .black.opacity(0.08), radius: 4, y: -1)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.isDirty)
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let settings = model.draft {
            ScrollView {
                VStack(alignment: .leading, spacing: PulsoSpace.s5) {
                    section("shell_privacy_friend_request_title") {
                        PulsoSegmentedControl(
                            [SocialFriendRequestPolicy.everyone, .peopleFollowedByMe, .mutualFollows, .nobody],
                            selection: Binding(get: { settings.friendRequestPolicy }, set: { value in model.edit { $0.friendRequestPolicy = value } })
                        ) { policy in
                            switch policy {
                            case .everyone: Text("shell_privacy_policy_everyone")
                            case .peopleFollowedByMe: Text("shell_privacy_policy_people_followed")
                            case .mutualFollows: Text("shell_privacy_policy_mutual_follows")
                            case .nobody: Text("shell_privacy_policy_nobody")
                            }
                        }
                    }

                    section("shell_privacy_direct_message_title", empty: settings.directMessagePolicy.isEmpty) {
                        PulsoCard {
                            VStack(spacing: 0) {
                                ForEach(Self.directMessageOrder, id: \.self) { audience in
                                    PulsoCheckbox(Text(audience.labelKey), isOn: Binding(
                                        get: { settings.directMessagePolicy.contains(audience) },
                                        set: { _ in model.edit { $0.directMessagePolicy = toggled($0.directMessagePolicy, audience, order: Self.directMessageOrder) } }
                                    ))
                                    .padding(.horizontal, PulsoSpace.s3)
                                    .padding(.vertical, PulsoSpace.s2)
                                }
                            }
                        }
                    }

                    section("shell_privacy_group_invite_title", empty: settings.groupInvitePolicy.isEmpty) {
                        PulsoCard {
                            VStack(spacing: 0) {
                                ForEach(Self.groupInviteOrder, id: \.self) { audience in
                                    PulsoCheckbox(Text(audience.labelKey), isOn: Binding(
                                        get: { settings.groupInvitePolicy.contains(audience) },
                                        set: { _ in model.edit { $0.groupInvitePolicy = toggled($0.groupInvitePolicy, audience, order: Self.groupInviteOrder) } }
                                    ))
                                    .padding(.horizontal, PulsoSpace.s3)
                                    .padding(.vertical, PulsoSpace.s2)
                                }
                            }
                        }
                    }

                    section("shell_privacy_visibility_title") {
                        PulsoCard {
                            VStack(spacing: 0) {
                                toggle("shell_privacy_show_friend_list", settings.showFriendList) { value in model.edit { $0.showFriendList = value } }
                                toggle("shell_privacy_show_following_list", settings.showFollowingList) { value in model.edit { $0.showFollowingList = value } }
                                toggle("shell_privacy_show_follower_list", settings.showFollowerList) { value in model.edit { $0.showFollowerList = value } }
                                toggle("shell_privacy_show_block_list", settings.showBlockList) { value in model.edit { $0.showBlockList = value } }
                            }
                        }
                    }
                }
                .padding(PulsoSpace.s4)
            }
        } else if let error = model.loadError {
            PulsoLoadErrorView(error) { Task { await model.load() } }
        } else {
            ProgressView()
        }
    }

    /** 一节：半粗小标题，下面控件；一个都没选时提示「没有人可以」。 */
    private func section(_ title: LocalizedStringKey, empty: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
            content()
            if empty {
                Text("shell_privacy_nobody_hint").font(.caption).foregroundStyle(palette.secondaryText)
            }
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: set)) {
            Text(title).font(.subheadline).foregroundStyle(palette.text)
        }
        .tint(palette.accent.step(9))
        .padding(.horizontal, PulsoSpace.s4)
        .padding(.vertical, PulsoSpace.s3)
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
