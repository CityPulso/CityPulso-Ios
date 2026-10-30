import CoreLocation
import MapKit
import PulsoLinkCore

/**
 * 给设备定位，把结果写进 [DeviceLocationStore]（唯一的写入方）（对应 Android `DeviceLocationBootstrap`）。
 * App 回到前台和点「定位到我」时运行，换了地方的手机能拿到新位置。自己从不弹权限：没有权限时继续用上次的位置。
 */
final class DeviceLocationBootstrap: Sendable {
    private static let currentFixTimeoutSeconds = 5.0
    /** 没怎么移动时保留上次的街道名。 */
    private static let keepLabelWithinM = 200.0

    private let store: DeviceLocationStore

    init(store: DeviceLocationStore) {
        self.store = store
    }

    /**
     * 先存上次的定位让搜索能开始，再换成新定位，最后用街道名替换坐标。
     * 返回新位置；没有权限或定位不到时返回已存的位置或 nil。
     */
    @discardableResult
    func refresh() async -> PickedLocation? {
        guard Self.hasPermission() else { return nil }
        if let last = await MainActor.run(body: { CLLocationManager().location }) {
            save(PickedLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude))
        }
        guard let fix = await currentFix() else { return store.location.value?.point }
        save(fix)
        if let label = await Self.streetLabel(fix), store.location.value?.point == fix {
            store.save(DeviceLocation(point: fix, label: label))
        }
        return fix
    }

    private static func hasPermission() -> Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    /** 一次新的定位，最多等 [currentFixTimeoutSeconds]，慢的 GPS 不会卡住调用方。 */
    private func currentFix() async -> PickedLocation? {
        let fix: PickedLocation?? = await withTimeoutOrNil(seconds: Self.currentFixTimeoutSeconds) {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return PickedLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    }
                }
            } catch {
                return nil
            }
            return nil
        }
        return fix ?? nil
    }

    /** 和上次位置差不多时保留街道名，否则先显示坐标。 */
    private func save(_ point: PickedLocation) {
        let previous = store.location.value
        let sameSpot = previous.map {
            !$0.label.isEmpty && haversineM($0.point.latitude, $0.point.longitude, point.latitude, point.longitude) <= Self.keepLabelWithinM
        } ?? false
        store.save(DeviceLocation(point: point, label: sameSpot ? previous!.label : Self.coordinateLabel(point)))
    }

    private static func coordinateLabel(_ point: PickedLocation) -> String {
        String(format: "%.4f, %.4f", locale: Locale(identifier: "en_US_POSIX"), point.latitude, point.longitude)
    }

    /** 街道、街区、城市（Android `reverseLabel`）。 */
    private static func streetLabel(_ point: PickedLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: point.latitude, longitude: point.longitude)) else {
            return nil
        }
        guard let item = try? await request.mapItems.first else { return nil }
        let label = item.address?.shortAddress ?? item.name
        return label?.isEmpty == false ? label : nil
    }
}
