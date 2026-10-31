import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 身份（对应 Android `ProfileIdentitiesScreen`）：账号安全入口、社区身份（配额、身份卡、改 CityPulso ID），
 * 最后提示组织和平台管理身份去网页版。
 */
struct ProfileIdentitiesView: View {
    @State private var model = ProfileIdentitiesModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s5) {
                PulsoCard {
                    NavigationLink(value: NearRoute.accountSecurity) {
                        PulsoSectionRow("account_security_title", systemImage: "lock.shield", supporting: String(localized: "account_security_entry_hint"))
                    }
                    .buttonStyle(.pulsoRow)
                }
                communityHeader
                if let profiles = model.profiles {
                    ForEach(profiles) { profile in
                        PulsoCard { identityCard(profile).padding(PulsoSpace.s5) }
                    }
                    ForEach(0..<max(ProfileIdentitiesModel.maxCommunityProfiles - profiles.count, 0), id: \.self) { _ in
                        PulsoCard {
                            Text("profile_identities_empty_slot").foregroundStyle(palette.secondaryText).padding(PulsoSpace.s5)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                PulsoCard {
                    HStack(spacing: PulsoSpace.s3) {
                        Image(systemName: "laptopcomputer").font(.title2).foregroundStyle(palette.text)
                        Text("profile_identities_web_apply_note").font(.subheadline).foregroundStyle(palette.secondaryText)
                    }
                    .padding(PulsoSpace.s5)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("profile_identities_title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observeProfiles() }
    }

    /** 区块头：图标、标题和说明、配额，下面一条强调色线（Android 身份页的分区头）。 */
    private var communityHeader: some View {
        VStack(spacing: PulsoSpace.s2) {
            HStack(alignment: .bottom, spacing: PulsoSpace.s3) {
                Image(systemName: ProfileRoleVisuals.kindSymbol(.community)).font(.title3).foregroundStyle(palette.secondaryText)
                VStack(alignment: .leading, spacing: PulsoSpace.half) {
                    Text("profile_identities_region_community_title").font(.headline).foregroundStyle(palette.text)
                    Text("profile_identities_region_community_hint").font(.footnote).foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 0)
                if let profiles = model.profiles {
                    Text(verbatim: localizedFormat("profile_identities_count", profiles.count, ProfileIdentitiesModel.maxCommunityProfiles))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Capsule().fill(palette.accent.step(9)).frame(height: 3)
        }
    }

    private func identityCard(_ profile: CommunityProfileItem) -> some View {
        let isCurrent = profile.profileId == model.currentProfileId
        return VStack(alignment: .leading, spacing: PulsoSpace.s4) {
            HStack(spacing: PulsoSpace.s3) {
                PulsoAvatar(url: model.avatarURL(profile), size: 56, systemImage: "person", fallbackText: profile.displayName)
                VStack(alignment: .leading, spacing: PulsoSpace.half) {
                    Group {
                        if let name = profile.displayName, !name.isEmpty { Text(verbatim: name) } else { Text("select_profile_unnamed") }
                    }
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    Text(languageKey(profile.profileLanguage)).font(.subheadline).foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Label("profile_identities_in_use", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, PulsoSpace.s3)
                        .padding(.vertical, PulsoSpace.s2)
                        .background(palette.accent.step(9), in: palette.chipShape)
                }
            }
            citypulsoId(profile, isCurrent: isCurrent)
            Label("select_profile_kind_community", systemImage: ProfileRoleVisuals.kindSymbol(.community))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent.step(11))
                .padding(.horizontal, PulsoSpace.s3)
                .padding(.vertical, PulsoSpace.s2)
                .background(palette.accent.step(3), in: palette.chipShape)
            let roles = ProfileRoleVisuals.sorted(profile.communityRoles.map(\.rawValue))
            if !roles.isEmpty {
                HStack(spacing: PulsoSpace.s2) {
                    ForEach(roles, id: \.self) { role in
                        ProfileRoleLabel(role: role)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(palette.text)
                            .frame(width: 40, height: 40)
                            .overlay { palette.innerShape.strokeBorder(palette.outlineVariant, lineWidth: pulsoHairline) }
                    }
                }
            }
            if isCurrent {
                Text("profile_identities_currently_active").font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent.step(11))
            }
        }
    }

    /** 「@ CityPulso ID」，当前身份可以点铅笔改。 */
    @ViewBuilder
    private func citypulsoId(_ profile: CommunityProfileItem, isCurrent: Bool) -> some View {
        if isCurrent, let draft = model.citypulsoIdDraft, draft.profileId == profile.profileId {
            VStack(alignment: .leading, spacing: PulsoSpace.s3) {
                PulsoTextField(
                    "profile_identities_citypulso_id_label",
                    text: Binding(get: { draft.value }, set: { model.setCitypulsoIdDraft($0) }),
                    hintText: model.citypulsoIdDraftValid ? String(localized: "profile_identities_citypulso_id_rule") : nil,
                    errorText: model.citypulsoIdDraftValid ? nil : String(localized: "profile_identities_citypulso_id_rule")
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                HStack(spacing: PulsoSpace.s3) {
                    Button("profile_identities_citypulso_id_cancel") { model.citypulsoIdDraft = nil }
                        .buttonStyle(.pulso(.soft, tone: .gray, fullWidth: true))
                    Button("profile_identities_citypulso_id_save") { Task { await model.saveCitypulsoId() } }
                        .buttonStyle(.pulso(fullWidth: true))
                        .disabled(!model.citypulsoIdDraftValid || model.savingCitypulsoId)
                }
            }
        } else {
            HStack(spacing: PulsoSpace.s2) {
                Image(systemName: "at").foregroundStyle(palette.secondaryText)
                Text(verbatim: profile.citypulsoId).font(.body.weight(.medium)).foregroundStyle(palette.secondaryText).textSelection(.enabled)
                if isCurrent {
                    Button { model.startCitypulsoIdEdit(profile) } label: {
                        Image(systemName: "pencil").foregroundStyle(palette.text).frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("profile_identities_citypulso_id_edit"))
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
