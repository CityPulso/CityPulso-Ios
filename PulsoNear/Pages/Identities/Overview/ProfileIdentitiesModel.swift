import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 身份页（对应 Android `ProfileIdentitiesViewModel`）。Near 只管社区身份；
 * 组织、平台管理身份在网页版申请和管理。
 */
@MainActor
@Observable
final class ProfileIdentitiesModel {
    /** 每个账号只有一个社区身份（后端 AuthAccountMaxCommunityProfiles）。 */
    static let maxCommunityProfiles = 1

    private(set) var profiles: [CommunityProfileItem]?
    private(set) var currentProfileId = ""
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

    var citypulsoIdDraftValid: Bool {
        guard let draft = citypulsoIdDraft else { return false }
        return (try? citypulsoIdPattern.wholeMatch(in: draft.value.trimmingCharacters(in: .whitespaces))) != nil
    }

    /** 跟着身份列表查询。 */
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
}
