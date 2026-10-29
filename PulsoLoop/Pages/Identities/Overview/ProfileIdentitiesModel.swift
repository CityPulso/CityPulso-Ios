import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一种社区角色申请（creator / coach）的表单状态。 */
struct IdentityApplyForm {
    static let minMotivation = 20

    var application: CommunityRoleApplicationItem?
    /** 「我的申请」已返回（包括没申请过）；之前表单区显示加载。 */
    var loaded = false
    var motivation = ""
    var submitting = false

    var motivationValid: Bool { motivation.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minMotivation }
}

/**
 * 身份页（对应 Android `ProfileIdentitiesViewModel`）。Loop 只管社区身份和社区角色申请（创作者 / 教练）；
 * 组织、平台管理身份在网页版申请和管理。
 */
@MainActor
@Observable
final class ProfileIdentitiesModel {
    /** 每个账号只有一个社区身份（后端 AuthAccountMaxCommunityProfiles）。 */
    static let maxCommunityProfiles = 1

    private(set) var profiles: [CommunityProfileItem]?
    private(set) var currentProfileId = ""
    private(set) var forms: [AuthCommunityRole: IdentityApplyForm] = [:]
    /** 正在编辑 CityPulso ID 的身份。 */
    var citypulsoIdDraft: (profileId: String, value: String)?
    private(set) var savingCitypulsoId = false

    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.authQueryStore) private var queries
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    func avatarURL(_ profile: CommunityProfileItem) -> URL? {
        ImageURLs.image(profile.avatarImageId, base: config.apiBaseURL)
    }

    func form(_ role: AuthCommunityRole) -> IdentityApplyForm {
        forms[role] ?? IdentityApplyForm()
    }

    func holds(_ role: AuthCommunityRole) -> Bool {
        (profiles ?? []).contains { $0.communityRoles.contains(role) }
    }

    var citypulsoIdDraftValid: Bool {
        guard let draft = citypulsoIdDraft else { return false }
        return (try? citypulsoIdPattern.wholeMatch(in: draft.value.trimmingCharacters(in: .whitespaces))) != nil
    }

    /** 身份列表和每种申请各自加载、各自出现，不整页等最慢的一个。 */
    func observeProfiles() async {
        let session = sessionStore.state.value
        currentProfileId = session.currentProfileId
        for await response in queries.profiles.stream(AuthProfilesKey(accountId: session.currentAccountId, kind: .community)) {
            switch response {
            case let .data(.community(list)): profiles = list.items
            case .data: profiles = []
            case .loading: break
            case let .error(error):
                if profiles == nil { profiles = [] }
                PulsoMessageCenter.shared.error(error, fallback: "profile_identities_load_failed")
            }
        }
    }

    func observeApplication(_ role: AuthCommunityRole) async {
        let session = sessionStore.state.value
        let key = MyCommunityRoleApplicationKey(accountId: session.currentAccountId, profileId: session.currentProfileId, role: role)
        for await response in queries.communityRoleApplications.stream(key) {
            switch response {
            case let .data(application):
                forms[role, default: IdentityApplyForm()].application = application
                forms[role, default: IdentityApplyForm()].loaded = true
            case .loading: break
            case let .error(error):
                forms[role, default: IdentityApplyForm()].loaded = true
                PulsoMessageCenter.shared.error(error, fallback: "profile_identities_load_failed")
            }
        }
    }

    func startCitypulsoIdEdit(_ profile: CommunityProfileItem) {
        guard profile.profileId == currentProfileId else { return }
        citypulsoIdDraft = (profile.profileId, profile.citypulsoId)
    }

    func setCitypulsoIdDraft(_ value: String) {
        citypulsoIdDraft?.value = String(value.prefix(64))
    }

    func saveCitypulsoId() async {
        guard let draft = citypulsoIdDraft, citypulsoIdDraftValid, !savingCitypulsoId else { return }
        savingCitypulsoId = true
        defer { savingCitypulsoId = false }
        do {
            try await authService.updateCitypulsoId(draft.value.trimmingCharacters(in: .whitespaces))
            citypulsoIdDraft = nil
            PulsoMessageCenter.shared.success("profile_identities_citypulso_id_saved")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "profile_identities_action_failed")
        }
    }

    func setMotivation(_ role: AuthCommunityRole, _ value: String) {
        forms[role, default: IdentityApplyForm()].motivation = String(value.prefix(2000))
    }

    func submit(_ role: AuthCommunityRole) async {
        let form = form(role)
        guard !form.submitting else { return }
        guard form.motivationValid else {
            PulsoMessageCenter.shared.error("profile_identities_apply_motivation_min")
            return
        }
        forms[role, default: IdentityApplyForm()].submitting = true
        do {
            try await authService.submitCommunityRoleApplication(
                SubmitCommunityRoleApplicationRequest(role: role, motivation: form.motivation.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            forms[role] = IdentityApplyForm(application: forms[role]?.application, loaded: true)
            PulsoMessageCenter.shared.success("profile_identities_apply_submitted")
        } catch {
            forms[role, default: IdentityApplyForm()].submitting = false
            PulsoMessageCenter.shared.error(error, fallback: "profile_identities_action_failed")
        }
    }
}
