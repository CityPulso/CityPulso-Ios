import AsyncAlgorithms
import Foundation

/** Preference 域门面：pages 不直接碰 [PreferenceRepository]。 */
public struct PreferenceService: Sendable {
    private let preferenceRepository: PreferenceRepository
    private let authService: AuthService
    private let sessionStore: AuthSessionStore
    private let config: PulsoCoreConfig

    public init(
        preferenceRepository: PreferenceRepository,
        authService: AuthService,
        sessionStore: AuthSessionStore,
        config: PulsoCoreConfig
    ) {
        self.preferenceRepository = preferenceRepository
        self.authService = authService
        self.sessionStore = sessionStore
        self.config = config
    }

    public var preference: StateBroadcast<ResolvedPreference> { preferenceRepository.preference }

    /** 底栏槽位按当前身份与本 App 规范化：该身份不可用的页和别的 App 才有的页不会出现。 */
    public var androidPreference: ResolvedAndroidPreference {
        preferenceRepository.preference.value.android
            .resolved(kind: sessionStore.state.value.currentProfileKind, supported: config.shellDestinations)
    }

    /** [androidPreference] 的变化流（先发当前值）。 */
    public func androidPreferenceValues() -> some AsyncSequence<ResolvedAndroidPreference, Never> {
        let supported = config.shellDestinations
        let kinds = sessionStore.state.values().map(\.currentProfileKind).removeDuplicates()
        let androids = preferenceRepository.preference.values().map(\.android).removeDuplicates()
        return combineLatest(androids, kinds)
            .map { android, kind in android.resolved(kind: kind, supported: supported) }
            .removeDuplicates()
    }

    /** [ResolvedPreference.theme] 的变化流（先发当前值）。 */
    public func themeSettingsValues() -> some AsyncSequence<PulsoThemeSettings, Never> {
        preferenceRepository.preference.values().map(\.theme).removeDuplicates()
    }

    public func update(_ transform: (inout ResolvedPreference) -> Void) {
        preferenceRepository.update(transform)
    }

    public func saveAndroid(_ next: ResolvedAndroidPreference) {
        preferenceRepository.saveAndroid(next)
    }

    public func saveTheme(_ settings: PulsoThemeSettings) {
        preferenceRepository.saveTheme(settings)
    }

    /**
     * 把本地偏好推到服务端 [kind] 身份上。未登录时什么都不做；网络 / API 失败直接抛
     *（本地副本已保存，调用方决定怎么提示）。服务端存 camelCase JSON，nil 字段不写出。
     */
    public func syncToServer(kind: ProfileKind) async throws {
        let session = sessionStore.state.value
        guard session.isAuthValid, session.hasSelectedProfile else { return }
        let data = try JSONEncoder().encode(preferenceRepository.preference.value.serverPreference)
        try await authService.updatePreference(kind: kind, preference: String(decoding: data, as: UTF8.self))
    }
}
