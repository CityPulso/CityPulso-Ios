import Foundation

/**
 * 设备 ID：首次生成 UUID 并持久化，之后稳定复用
 *（对应 WEB `ensureDeviceIdStorage`；随所有 auth 请求上送）。
 */
public actor DeviceIdProvider {
    private static let key = "device_id"
    private let defaults: UserDefaults
    private var cached: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func ensureDeviceId() -> String {
        if let cached { return cached }
        let deviceId = defaults.string(forKey: Self.key) ?? {
            let generated = UUID().uuidString.lowercased()
            defaults.set(generated, forKey: Self.key)
            return generated
        }()
        cached = deviceId
        return deviceId
    }
}
