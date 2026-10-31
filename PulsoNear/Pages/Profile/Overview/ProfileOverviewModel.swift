import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 我的资料页（对应 Android `ProfileOverviewViewModel`）：[ProfileStore] 是唯一来源，别处改了资料这里跟着变。
 * 发起 / 参加的活动数要等活动数据移植（第 4–6 组）后接上。
 */
@MainActor
@Observable
final class ProfileOverviewModel {
    private(set) var info: CurrentFullAccountInformation?
    private(set) var loadError: UiError?
    private(set) var refreshing = false
    let avatar = AvatarUploadModel()

    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.profileBootstrap) private var profileBootstrap
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.authService) private var authService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.nearActivityServices) private var services
    @ObservationIgnored private var hostedByKind: [NearActivityKind: Int] = [:]
    @ObservationIgnored private var joinedByKind: [NearActivityKind: Int] = [:]
    /** 头部数字；没回来之前是 nil（显示 `-`）。活动 = 各活动类型的发起 + 参加。 */
    private(set) var followingCount: Int?
    private(set) var followerCount: Int?
    private(set) var activityCount: Int?
    /** 头部下面的活动中心（Android 资料页同样接 `activityCenterSection`）。 */
    let activity = ActivityCenterModel()

    var avatarURL: URL? { ImageURLs.image(info?.avatarImageId, base: config.apiBaseURL) }

    var backgroundURLs: [URL] {
        (info?.backgrounds ?? []).compactMap { ImageURLs.image($0.imageId, base: config.apiBaseURL) }
    }

    /** 有创作者角色：账号状态旁边一个小徽标。 */
    var isCreator: Bool { info?.roleLabels.contains(AuthCommunityRole.creator.rawValue) == true }

    var location: String? {
        let parts = [info?.city, info?.country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /** 账号状态首字母大写（与 Android 一样直接显示后端值）。 */
    var accountStatusLabel: String? {
        let raw = (info?.accountStatus ?? "").trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? nil : raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /** 跟着 [ProfileStore]；页面消失时随 `.task` 取消。 */
    /** 关注 / 粉丝数，各自填上；每次数字失效都重拉。 */
    func observeRelationCounts() async {
        await concurrently([
            { for await count in self.socialService.relationCount(.following) { self.followingCount = count } },
            { for await count in self.socialService.relationCount(.followers) { self.followerCount = count } },
        ])
    }

    /** 资料页选完喜欢的活动：保存到资料，资料重拉后头部跟着变。 */
    func saveFavoriteActivities(_ next: [FavoriteActivity]) async {
        guard next != info?.favoriteActivities else { return }
        var patch = PatchProfileRequest()
        patch.favoriteActivities = next
        do {
            try await authService.patchProfile(kind: .community, patch)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "profile_edit_save_failed")
        }
    }

    /** 各活动类型的发起 / 参加数加起来；身份变了重算。页面消失时随 `.task` 取消。 */
    func observeCounts() async {
        let session = sessionStore.state.value
        let accountId = session.currentAccountId
        let profileId = session.currentProfileId
        guard !accountId.isEmpty, !profileId.isEmpty else { return }
        hostedByKind = [:]
        joinedByKind = [:]
        var operations: [@MainActor () async -> Void] = []
        for (kind, service) in services {
            let hostedStream = service.hostedActivities(accountId: accountId, profileId: profileId, hostedProfileId: profileId, limit: 100)
            let joinedStream = service.myRegistrations(ActivityTypeRegistrationsQuery(accountId: accountId, profileId: profileId, limit: 100))
            operations.append {
                for await case let .data(items) in hostedStream {
                    self.hostedByKind[kind] = items.count
                    self.publishCounts()
                }
            }
            operations.append {
                for await case let .data(items) in joinedStream {
                    self.joinedByKind[kind] = items.count
                    self.publishCounts()
                }
            }
        }
        await concurrently(operations)
    }

    /** 每种活动类型都回答了才换数字（Android `sumOrNull`）。 */
    private func publishCounts() {
        guard hostedByKind.count == services.count, joinedByKind.count == services.count else { return }
        activityCount = hostedByKind.values.reduce(0, +) + joinedByKind.values.reduce(0, +)
    }

    func observe() async {
        for await current in profileStore.current.values() {
            if let current { info = current }
        }
    }

    /** 首次静默加载不显示指示；下拉刷新失败而页面已有资料时只提示。 */
    func refresh(showIndicator: Bool) async {
        refreshing = showIndicator
        loadError = nil
        defer { refreshing = false }
        do {
            try await profileBootstrap.refresh()
        } catch {
            if info == nil {
                loadError = UiError(error)
            } else {
                PulsoMessageCenter.shared.error(error, fallback: "profile_overview_refresh_failed")
            }
        }
    }

    func copyCitypulsoId() {
        guard let id = info?.citypulsoId, !id.isEmpty else { return }
        UIPasteboard.general.string = id
        PulsoMessageCenter.shared.success("profile_overview_id_copied")
    }
}

/** 性别：预设 wire → 文案，自定义原文显示（Android `formatGenderLabel`）。 */
enum GenderOption: String, CaseIterable, Identifiable {
    case male
    case female
    case nonBinary = "non-binary"
    case preferNot = "prefer not to say"

    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .male: "profile_edit_gender_male"
        case .female: "profile_edit_gender_female"
        case .nonBinary: "profile_edit_gender_non_binary"
        case .preferNot: "profile_edit_gender_prefer_not"
        }
    }

    var labelResource: String.LocalizationValue {
        switch self {
        case .male: "profile_edit_gender_male"
        case .female: "profile_edit_gender_female"
        case .nonBinary: "profile_edit_gender_non_binary"
        case .preferNot: "profile_edit_gender_prefer_not"
        }
    }

    static func preset(_ raw: String) -> GenderOption? {
        GenderOption(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/** 生日：接口可能回 RFC3339，表单和显示都用 `YYYY-MM-DD` 那一天。 */
enum Birthday {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        return parser.date(from: String(raw.prefix(10)))
    }

    static func day(_ date: Date) -> String {
        parser.string(from: date)
    }

    /** PATCH 用：`YYYY-MM-DD` → UTC 零点 RFC3339（Android `toBirthdayWireIso`）。 */
    static func wire(_ day: String) -> String {
        "\(day)T00:00:00.000Z"
    }

    static func display(_ raw: String?) -> String? {
        date(raw).map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)) }
    }
}

extension PulsoLanguage {
    /** 资料里的语言名（「简体中文」「English」…，跟着界面语言写）。 */
    var profileLabelResource: String.LocalizationValue {
        switch self {
        case .zh: "profile_lang_zh"
        case .zhHant: "profile_lang_zh_hant"
        case .en: "profile_lang_en"
        case .fr: "profile_lang_fr"
        }
    }

    var profileLabelKey: LocalizedStringKey {
        switch self {
        case .zh: "profile_lang_zh"
        case .zhHant: "profile_lang_zh_hant"
        case .en: "profile_lang_en"
        case .fr: "profile_lang_fr"
        }
    }
}
