import Foundation

/**
 * 登录后用服务端 preference 覆盖本地（对应 WEB `useApplyPreferenceOnLoad`）：
 * - [ProfileStore] 填入完整档案且 profile.preference 非空 → parse + replace；
 * - 服务端尚无 preference 时保留本地，避免用 defaults 冲掉主题/地图设置；
 * - 本地-only 字段 mapRich / mapNearbyRange 从当前本地值保留；
 * - 服务端尚无 android 时保留本地底栏；有槽位但缺某个 app 的桌面图标时保留本地图标档位。
 */
public final class PreferenceBootstrap: @unchecked Sendable {
    /** 已应用的 profile + preference；同键不重复 replace。 */
    private struct AppliedKey: Hashable {
        let profileId: String
        let accountId: String
        let preference: Preference
    }

    private let profileStore: ProfileStore
    private let preferenceRepository: PreferenceRepository
    private let config: PulsoCoreConfig
    private let lock = NSLock()
    private var lastAppliedKey: AppliedKey?
    private var watcher: Task<Void, Never>?

    public init(profileStore: ProfileStore, preferenceRepository: PreferenceRepository, config: PulsoCoreConfig) {
        self.profileStore = profileStore
        self.preferenceRepository = preferenceRepository
        self.config = config
    }

    /** App 启动时调用一次。 */
    public func start() {
        let profiles = profileStore.current.values()
        let task = Task { [weak self] in
            for await info in profiles {
                guard let self else { return }
                if let info {
                    applyFromProfile(info)
                } else {
                    lock.withLock { lastAppliedKey = nil }
                }
            }
        }
        lock.withLock { watcher = task }
    }

    /**
     * 把档案上的服务端 preference 同步写入本地。
     * - Returns: true 表示主题或语言相对本地有变化。
     */
    @discardableResult
    public func applyFromProfile(_ info: CurrentFullAccountInformation) -> Bool {
        guard let server = info.preference else { return false }
        let key = AppliedKey(profileId: info.profileId ?? "", accountId: info.accountId, preference: server)
        return lock.withLock {
            guard lastAppliedKey != key else { return false }
            lastAppliedKey = key
            var parsed = ResolvedPreference(server: server, kind: info.kind, supported: config.shellDestinations)
            let current = preferenceRepository.preference.value
            parsed.map.mapRich = current.map.mapRich
            parsed.map.mapNearbyRange = current.map.mapNearbyRange
            parsed.android = .mergeServer(server.android, parsed: parsed.android, local: current.android)
            preferenceRepository.replace(parsed)
            debugLog("Server preference applied")
            return current.theme != parsed.theme || current.language != parsed.language
        }
    }

    deinit {
        watcher?.cancel()
    }
}
