import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 我的资料页（对应 Android `ProfileOverviewViewModel`）：[ProfileStore] 是唯一来源，别处改了资料这里跟着变。
 * 发起 / 参加数是所有运动加起来（每种最多 100 条，含已结束），每个运动都回来了才更新。
 */
@MainActor
@Observable
final class ProfileOverviewModel {
    private(set) var info: CurrentFullAccountInformation?
    private(set) var loadError: UiError?
    private(set) var refreshing = false
    private(set) var hostedCount = 0
    private(set) var joinedCount = 0
    let avatar = AvatarUploadModel()
    let activity = ActivityCenterModel()

    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.profileBootstrap) private var profileBootstrap
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored @Injected(\.loopSportServices) private var services
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored private var hostedBySport: [LoopSport: Int] = [:]
    @ObservationIgnored private var joinedBySport: [LoopSport: Int] = [:]

    var avatarURL: URL? { ImageURLs.image(info?.avatarImageId, base: config.apiBaseURL) }

    var backgroundURLs: [URL] {
        (info?.backgrounds ?? []).compactMap { ImageURLs.image($0.imageId, base: config.apiBaseURL) }
    }

    var roles: [String] { ProfileRoleVisuals.sorted(info?.roleLabels ?? []) }

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
    func observe() async {
        for await current in profileStore.current.values() {
            if let current { info = current }
        }
    }

    /** 各运动的发起 / 参加数加起来；身份变了重算。页面消失时随 `.task` 取消。 */
    func observeCounts() async {
        let session = sessionStore.state.value
        let accountId = session.currentAccountId
        let profileId = session.currentProfileId
        guard !accountId.isEmpty, !profileId.isEmpty else { return }
        hostedBySport = [:]
        joinedBySport = [:]
        var operations: [@MainActor () async -> Void] = []
        for (sport, service) in services {
            let hostedStream = service.hostedEvents(accountId: accountId, profileId: profileId, hostedProfileId: profileId, limit: 100)
            let joinedStream = service.myRegistrations(SportRegistrationsQuery(accountId: accountId, profileId: profileId, limit: 100))
            operations.append {
                for await case let .data(items) in hostedStream {
                    self.hostedBySport[sport] = items.count
                    self.publishCounts()
                }
            }
            operations.append {
                for await case let .data(items) in joinedStream {
                    self.joinedBySport[sport] = items.count
                    self.publishCounts()
                }
            }
        }
        await concurrently(operations)
    }

    /** 每个运动都回答了才换数字（Android `sumOrNull`）。 */
    private func publishCounts() {
        guard hostedBySport.count == services.count, joinedBySport.count == services.count else { return }
        hostedCount = hostedBySport.values.reduce(0, +)
        joinedCount = joinedBySport.values.reduce(0, +)
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
