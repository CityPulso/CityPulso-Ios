import Foundation

/**
 * 全量偏好持久化（对应 WEB PreferenceStore "pulsolink-preference"：
 * language / theme / map / event / billing / android）。整体序列化为一个 JSON 值存 UserDefaults。
 */
public final class PreferenceRepository: @unchecked Sendable {
    private static let key = "preference"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public let preference: StateBroadcast<ResolvedPreference>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ResolvedPreference.self, from: $0) }
        preference = StateBroadcast(stored ?? .default)
    }

    /** 整体替换（对应 WEB replacePreference——服务端偏好落地时使用）。 */
    public func replace(_ next: ResolvedPreference) {
        update { $0 = next }
    }

    /** 读-改-写局部更新（对应 WEB setPreference patch 语义）。 */
    public func update(_ transform: (inout ResolvedPreference) -> Void) {
        lock.withLock {
            var next = preference.value
            transform(&next)
            if let data = try? JSONEncoder().encode(next) {
                defaults.set(data, forKey: Self.key)
            }
            preference.set(next)
        }
    }

    public func saveTheme(_ settings: PulsoThemeSettings) {
        update { $0.theme = settings }
    }

    public func saveAndroid(_ next: ResolvedAndroidPreference) {
        update { $0.android = next }
    }
}
