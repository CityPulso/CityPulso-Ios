import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 身份（对应 Android `ProfileIdentitiesScreen`）：账号安全入口、社区身份（配额、身份卡、改 CityPulso ID），
 * 最后提示组织和平台管理身份去网页版。
 */
struct ProfileIdentitiesView: View {
    @State private var model = ProfileIdentitiesModel()

    var body: some View {
        Form {
            Section {
                NavigationLink(value: NearRoute.accountSecurity) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("account_security_title")
                            Text("account_security_entry_hint").font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                }
            }

            Section {
                if let profiles = model.profiles {
                    ForEach(profiles) { profile in
                        identityCard(profile)
                    }
                    ForEach(0..<max(ProfileIdentitiesModel.maxCommunityProfiles - profiles.count, 0), id: \.self) { _ in
                        Text("profile_identities_empty_slot").foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                HStack {
                    Label("profile_identities_region_community_title", systemImage: ProfileRoleVisuals.kindSymbol(.community))
                    Spacer()
                    if let profiles = model.profiles {
                        Text(verbatim: localizedFormat("profile_identities_count", profiles.count, ProfileIdentitiesModel.maxCommunityProfiles))
                    }
                }
            } footer: {
                Text("profile_identities_region_community_hint")
            }

            Section {
                Label("profile_identities_web_apply_note", systemImage: "desktopcomputer")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("profile_identities_title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observeProfiles() }
    }

    @ViewBuilder
    private func identityCard(_ profile: CommunityProfileItem) -> some View {
        let isCurrent = profile.profileId == model.currentProfileId
        HStack(spacing: 12) {
            PulsoAvatar(url: model.avatarURL(profile), size: 48, systemImage: "person", fallbackText: profile.displayName)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Group {
                        if let name = profile.displayName, !name.isEmpty { Text(verbatim: name) } else { Text("select_profile_unnamed") }
                    }
                    .font(.headline)
                    if isCurrent {
                        Text("profile_identities_in_use")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                            .foregroundStyle(.tint)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(ProfileRoleVisuals.sorted(profile.communityRoles.map(\.rawValue)), id: \.self) { role in
                        ProfileRoleLabel(role: role).labelStyle(.iconOnly).foregroundStyle(.secondary)
                    }
                    Text(languageKey(profile.profileLanguage)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if isCurrent, let draft = model.citypulsoIdDraft, draft.profileId == profile.profileId {
            VStack(alignment: .leading, spacing: 6) {
                TextField("profile_identities_citypulso_id_label", text: Binding(get: { draft.value }, set: model.setCitypulsoIdDraft))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("profile_identities_citypulso_id_rule")
                    .font(.footnote)
                    .foregroundStyle(model.citypulsoIdDraftValid ? Color.secondary : Color.red)
                HStack {
                    Button("profile_identities_citypulso_id_cancel", role: .cancel) { model.citypulsoIdDraft = nil }
                    Spacer()
                    Button("profile_identities_citypulso_id_save") { Task { await model.saveCitypulsoId() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.citypulsoIdDraftValid || model.savingCitypulsoId)
                }
                .buttonStyle(.borderless)
            }
        } else {
            LabeledContent("profile_identities_citypulso_id_label") {
                HStack {
                    Text(verbatim: profile.citypulsoId).textSelection(.enabled)
                    if isCurrent {
                        Button("profile_identities_citypulso_id_edit", systemImage: "pencil") { model.startCitypulsoIdEdit(profile) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func languageKey(_ language: PulsoLanguage) -> LocalizedStringKey {
        switch language {
        case .zh: "profile_lang_zh"
        case .zhHant: "profile_lang_zh_hant"
        case .en: "profile_lang_en"
        case .fr: "profile_lang_fr"
        }
    }
}
