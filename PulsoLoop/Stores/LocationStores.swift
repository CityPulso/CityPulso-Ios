import Foundation
import PulsoLinkCore

/** 查询中心坐标（地图 / 附近列表 / 选点共用）。 */
struct PickedLocation: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

/** 设备最后一次定位的位置和地名。 */
struct DeviceLocation: Hashable, Sendable {
    let point: PickedLocation
    let label: String
}

/**
 * 设备自己的位置，跨启动保存，地图、附近列表和选点一打开就有位置（对应 Android `DeviceLocationStore`）。
 * 只有 [DeviceLocationBootstrap] 写（一次 GPS 定位）；其他地方只读。
 */
final class DeviceLocationStore: Sendable {
    private static let latitudeKey = "device-location.latitude"
    private static let longitudeKey = "device-location.longitude"
    private static let labelKey = "device-location.label"

    private nonisolated(unsafe) let defaults: UserDefaults
    let location: StateBroadcast<DeviceLocation?>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored: DeviceLocation? = if defaults.object(forKey: Self.latitudeKey) != nil, defaults.object(forKey: Self.longitudeKey) != nil {
            DeviceLocation(
                point: PickedLocation(latitude: defaults.double(forKey: Self.latitudeKey), longitude: defaults.double(forKey: Self.longitudeKey)),
                label: defaults.string(forKey: Self.labelKey) ?? ""
            )
        } else {
            nil
        }
        location = StateBroadcast(stored)
    }

    func save(_ location: DeviceLocation) {
        defaults.set(location.point.latitude, forKey: Self.latitudeKey)
        defaults.set(location.point.longitude, forKey: Self.longitudeKey)
        defaults.set(location.label, forKey: Self.labelKey)
        self.location.set(location)
    }
}

/**
 * 附近搜索的中心（活动和球馆列表、发起、选点）：本次打开 App 时用户选的地点，否则是设备自己的位置
 *（对应 Android `NearbyQueryLocationStore`）。选的地点只在本次有效，下次打开又围绕用户自己搜索。
 */
final class NearbyQueryLocationStore: Sendable {
    /** 选的地点离设备不到这么多米时，算「我在这儿」，继续跟随 GPS。 */
    private static let followDeviceWithinM = 100.0

    private let device: DeviceLocationStore
    private let picked = StateBroadcast<DeviceLocation?>(nil)

    init(device: DeviceLocationStore) {
        self.device = device
    }

    /** 当前搜索中心（选的地点优先，其次设备位置）。 */
    var current: DeviceLocation? {
        picked.value ?? device.location.value
    }

    /** 搜索中心的变化流：先发当前值，选点或设备位置变了再发。 */
    func values() -> AsyncStream<DeviceLocation?> {
        let pairs = combineLatest(picked, device.location)
        return AsyncStream { continuation in
            let task = Task {
                for await (pick, own) in pairs {
                    continuation.yield(pick ?? own)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /** 在 [location] 周围搜索直到关掉 App；就在设备旁边的地点继续跟随 GPS。 */
    func set(_ location: PickedLocation, label: String) {
        let own = device.location.value?.point
        let nearDevice = own.map {
            haversineM($0.latitude, $0.longitude, location.latitude, location.longitude) <= Self.followDeviceWithinM
        } ?? false
        picked.set(nearDevice ? nil : DeviceLocation(point: location, label: label))
    }
}

/** 搜索 / 球馆搜索把一个点交给地图页 flyTo 的一次性焦点（Android `ExploreFocusStore`）。 */
struct ExploreFocus: Hashable, Sendable {
    var eventId: String?
    var latitude: Double
    var longitude: Double
    var venueId: String?
}

final class ExploreFocusStore: Sendable {
    let focus = StateBroadcast<ExploreFocus?>(nil)

    func request(_ next: ExploreFocus) {
        focus.set(next)
    }

    func consume() -> ExploreFocus? {
        let current = focus.value
        focus.set(nil)
        return current
    }
}
