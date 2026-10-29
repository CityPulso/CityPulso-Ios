import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 编辑资料表单（对应 Android `ProfileEditForm`）。生日用 `YYYY-MM-DD`，空串表示没填。 */
struct ProfileEditForm: Equatable {
    /** 走 PUT /auth/me/citypulso-id，不在 PATCH profile 里。 */
    var citypulsoId = ""
    var profileLanguage: PulsoLanguage = .en
    var displayName = ""
    var firstName = ""
    var lastName = ""
    var city = ""
    var country = ""
    var timezone = ""
    var website = ""
    var gender = ""
    var birthday = ""
    var bio = ""
    var favoriteSports: [FavoriteSport] = []

    init() {}

    init(_ info: CurrentFullAccountInformation) {
        citypulsoId = info.citypulsoId ?? ""
        profileLanguage = info.profileLanguage ?? .en
        displayName = info.displayName ?? ""
        firstName = info.firstName ?? ""
        lastName = info.lastName ?? ""
        city = info.city ?? ""
        country = info.country ?? ""
        timezone = info.timezone ?? ""
        website = info.website ?? ""
        gender = info.gender ?? ""
        birthday = Birthday.date(info.birthday).map(Birthday.day) ?? ""
        bio = info.bio ?? ""
        favoriteSports = info.favoriteSports
    }

    /** 每个字段：没动过（等于上次的服务端值）就跟新的服务端值走，改过的保留（Android `mergeServer`）。 */
    static func merge(previous: ProfileEditForm, edited: ProfileEditForm, server: ProfileEditForm) -> ProfileEditForm {
        func pick<T: Equatable>(_ path: WritableKeyPath<ProfileEditForm, T>) -> T {
            edited[keyPath: path] == previous[keyPath: path] ? server[keyPath: path] : edited[keyPath: path]
        }
        var merged = ProfileEditForm()
        merged.citypulsoId = pick(\.citypulsoId)
        merged.profileLanguage = pick(\.profileLanguage)
        merged.displayName = pick(\.displayName)
        merged.firstName = pick(\.firstName)
        merged.lastName = pick(\.lastName)
        merged.city = pick(\.city)
        merged.country = pick(\.country)
        merged.timezone = pick(\.timezone)
        merged.website = pick(\.website)
        merged.gender = pick(\.gender)
        merged.birthday = pick(\.birthday)
        merged.bio = pick(\.bio)
        merged.favoriteSports = pick(\.favoriteSports)
        return merged
    }
}

/**
 * 编辑资料（对应 Android `ProfileEditViewModel`）。[ProfileStore] 是唯一来源：别处的改动（身份页改 CityPulso ID、
 * 头像、另一台设备）会出现在这里，没动过的字段换成新值，改过的保留。
 * 离开页面时自动保存：没改 → 直接走；改了且有效 → 保存；无效或失败 → 提示原因。
 */
@MainActor
@Observable
final class ProfileEditModel {
    var form = ProfileEditForm()
    private(set) var baseline = ProfileEditForm()
    private(set) var loaded = false
    private(set) var loadError: UiError?
    private(set) var saving = false
    private(set) var avatarURL: URL?
    let avatar = AvatarUploadModel()

    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.profileBootstrap) private var profileBootstrap
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    static let shortFieldMax = 100

    var isDirty: Bool { form != baseline }
    var websiteError: Bool {
        let value = form.website.trimmingCharacters(in: .whitespaces)
        return !value.isEmpty && !value.hasPrefix("http://") && !value.hasPrefix("https://")
    }
    var citypulsoIdError: Bool { (try? citypulsoIdPattern.wholeMatch(in: form.citypulsoId.trimmingCharacters(in: .whitespaces))) == nil }
    var displayNameError: Bool { form.displayName.count > 150 }
    var bioError: Bool { form.bio.count > 5000 }
    var canSave: Bool {
        isDirty && !citypulsoIdError && !displayNameError && !bioError && !websiteError
            && [form.firstName, form.lastName, form.city, form.country, form.timezone, form.gender, form.website]
            .allSatisfy { $0.count <= Self.shortFieldMax }
    }

    func observe() async {
        for await info in profileStore.current.values() {
            guard let info else { continue }
            let server = ProfileEditForm(info)
            form = loaded ? ProfileEditForm.merge(previous: baseline, edited: form, server: server) : server
            baseline = server
            avatarURL = ImageURLs.image(info.avatarImageId, base: config.apiBaseURL)
            loaded = true
            loadError = nil
        }
    }

    func refresh() async {
        loadError = nil
        do {
            try await profileBootstrap.refresh()
        } catch {
            if loaded {
                PulsoMessageCenter.shared.error(error, fallback: "profile_edit_load_failed")
            } else {
                loadError = UiError(error)
            }
        }
    }

    /** 加一项或去掉一项，按固定顺序；已选满 [FavoriteSport.max] 时不能再加。 */
    func toggleFavoriteSport(_ sport: FavoriteSport) {
        guard form.favoriteSports.contains(sport) || form.favoriteSports.count < FavoriteSport.max else { return }
        form.favoriteSports = toggled(form.favoriteSports, sport, order: FavoriteSport.allCases)
    }

    /** 离开时保存；返回 false 表示有错没保存（已经提示过）。 */
    @discardableResult
    func saveIfNeeded() async -> Bool {
        guard loaded, isDirty, !saving else { return true }
        guard canSave else {
            PulsoMessageCenter.shared.error(
                citypulsoIdError ? "profile_identities_citypulso_id_rule"
                    : websiteError ? "profile_edit_website_invalid"
                    : "profile_edit_fix_invalid"
            )
            return false
        }
        saving = true
        defer { saving = false }
        let edited = form
        do {
            let citypulsoId = edited.citypulsoId.trimmingCharacters(in: .whitespaces)
            if citypulsoId != baseline.citypulsoId {
                try await authService.updateCitypulsoId(citypulsoId)
                baseline.citypulsoId = citypulsoId
            }
            if let patch = Self.sparsePatch(base: baseline, form: edited) {
                try await authService.patchProfile(kind: .community, patch)
            }
            baseline = edited
            return true
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "profile_edit_save_failed")
            return false
        }
    }

    /** 只带改过的字段（Android `buildSparsePatch`）；没改返回 nil。 */
    static func sparsePatch(base: ProfileEditForm, form: ProfileEditForm) -> PatchProfileRequest? {
        func changed(_ path: KeyPath<ProfileEditForm, String>) -> String? {
            let next = form[keyPath: path].trimmingCharacters(in: .whitespacesAndNewlines)
            return next == base[keyPath: path].trimmingCharacters(in: .whitespacesAndNewlines) ? nil : next
        }
        var patch = PatchProfileRequest()
        patch.profileLanguage = form.profileLanguage == base.profileLanguage ? nil : form.profileLanguage
        patch.displayName = changed(\.displayName)
        patch.firstName = changed(\.firstName)
        patch.lastName = changed(\.lastName)
        patch.city = changed(\.city)
        patch.country = changed(\.country)
        patch.timezone = changed(\.timezone)
        patch.website = changed(\.website)
        patch.gender = changed(\.gender)
        patch.birthday = changed(\.birthday).flatMap { $0.isEmpty ? nil : Birthday.wire($0) }
        patch.bio = changed(\.bio)
        patch.favoriteSports = form.favoriteSports == base.favoriteSports ? nil : form.favoriteSports
        let empty = patch.profileLanguage == nil && patch.displayName == nil && patch.firstName == nil
            && patch.lastName == nil && patch.city == nil && patch.country == nil && patch.timezone == nil
            && patch.website == nil && patch.gender == nil && patch.birthday == nil && patch.bio == nil
            && patch.favoriteSports == nil
        return empty ? nil : patch
    }
}
