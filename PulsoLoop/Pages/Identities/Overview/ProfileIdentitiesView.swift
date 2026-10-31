import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 身份（对应 Android `ProfileIdentitiesScreen`）：账号安全入口、社区身份（配额、身份卡、改 CityPulso ID）、
 * 创作者 / 教练申请，最后提示组织和平台管理身份去网页版。
 */
struct ProfileIdentitiesView: View {
    @State private var model = ProfileIdentitiesModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s5) {
                PulsoCard {
                    NavigationLink(value: LoopRoute.accountSecurity) {
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
                // 已经有这个角色、也没有申请记录时不显示申请卡（Android 身份页）。
                ForEach(AuthCommunityRole.applicable.filter { !(model.holds($0) && model.form($0).application == nil) }, id: \.self) { role in
                    applyCard(role)
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
        .task { await model.observeApplication(.creator) }
        .task { await model.observeApplication(.coach) }
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
                    Text(profile.profileLanguage.profileLabelKey).font(.subheadline).foregroundStyle(palette.secondaryText)
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

    /** 申请成为创作者 / 教练：一张卡，标题、说明、多行输入框和提交按钮（Android 身份页）。 */
    private func applyCard(_ role: AuthCommunityRole) -> some View {
        let copy = ApplyCopy(role)
        let form = model.form(role)
        let status = form.application?.status
        let canApply = status != .pending && status != .approved && !model.holds(role)
        return PulsoCard {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text(status == .rejected ? "profile_identities_apply_reapply_title" : copy.title).font(.headline).foregroundStyle(palette.text)
                if !form.loaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    switch status {
                    case .pending:
                        statusRow("profile_identities_apply_status_pending", .orange, Text(copy.pending))
                    case .approved:
                        statusRow("profile_identities_apply_status_approved", .green, Text(copy.approved))
                    case .rejected:
                        let reason = form.application?.rejectionReason.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                            ?? String(localized: "profile_identities_apply_rejected_no_reason")
                        statusRow("profile_identities_apply_status_rejected", palette.error, Text(verbatim: localizedFormat("profile_identities_apply_rejected_message", reason)))
                    case nil:
                        EmptyView()
                    }
                    if canApply {
                        Text(copy.intro).font(.subheadline).foregroundStyle(palette.secondaryText)
                        TextField("", text: Binding(get: { form.motivation }, set: { model.setMotivation(role, $0) }), prompt: Text(copy.placeholder), axis: .vertical)
                            .lineLimit(5...10)
                            .padding(PulsoSpace.s4)
                            .frame(minHeight: 140, alignment: .topLeading)
                            .overlay { palette.textAreaShape.strokeBorder(palette.outline, lineWidth: pulsoHairline) }
                        if !form.motivation.isEmpty, !form.motivationValid {
                            Text("profile_identities_apply_motivation_min").font(.footnote).foregroundStyle(palette.error)
                        }
                        Button {
                            Task { await model.submit(role) }
                        } label: {
                            if form.submitting { ProgressView() } else { Text("profile_identities_apply_submit") }
                        }
                        .buttonStyle(.pulso(fullWidth: true))
                        .environment(\.pulsoControlSize, .comfortable)
                        .disabled(!form.motivationValid || form.submitting)
                    }
                }
            }
            .padding(PulsoSpace.s5)
        }
    }

    private func statusRow(_ label: LocalizedStringKey, _ tint: Color, _ body: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(tint)
            body
        }
    }
}

/** 每种社区角色申请的文案（Android `applyCopy`）。 */
private struct ApplyCopy {
    let title: LocalizedStringKey
    let intro: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let pending: LocalizedStringKey
    let approved: LocalizedStringKey

    init(_ role: AuthCommunityRole) {
        switch role {
        case .coach:
            title = "profile_identities_apply_coach_title"
            intro = "profile_identities_apply_coach_intro"
            placeholder = "profile_identities_apply_coach_placeholder"
            pending = "profile_identities_apply_coach_pending"
            approved = "profile_identities_apply_coach_approved"
        case .creator, .pulser:
            title = "profile_identities_apply_creator_title"
            intro = "profile_identities_apply_creator_intro"
            placeholder = "profile_identities_apply_creator_placeholder"
            pending = "profile_identities_apply_creator_pending"
            approved = "profile_identities_apply_creator_approved"
        }
    }
}
