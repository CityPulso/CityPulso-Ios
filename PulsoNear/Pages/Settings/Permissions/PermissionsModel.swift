import AVFoundation
import CoreLocation
import Photos
import SwiftUI
import UIKit
import UserNotifications

/** 系统授权页里的一项（对应 Android `PermissionsScreen` 的每张卡片）。 */
enum AppPermission: CaseIterable, Identifiable {
    case location
    case notifications
    case camera
    case photos
    case microphone

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .location: "settings_permission_location_title"
        case .notifications: "settings_permission_notifications_title"
        case .camera: "settings_permission_camera_title"
        case .photos: "settings_permission_photos_title"
        case .microphone: "settings_permission_microphone_title"
        }
    }

    var bodyKey: LocalizedStringKey {
        switch self {
        case .location: "settings_permission_location_body"
        case .notifications: "settings_permission_notifications_body"
        case .camera: "settings_permission_camera_body"
        case .photos: "settings_permission_photos_body"
        case .microphone: "settings_permission_microphone_body"
        }
    }

    var systemImage: String {
        switch self {
        case .location: "location"
        case .notifications: "bell"
        case .camera: "camera"
        case .photos: "photo.on.rectangle"
        case .microphone: "mic"
        }
    }
}

/** 授权状态：还没问过的才能在 App 里弹系统询问；问过之后只能去系统设置改。 */
enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

/**
 * 系统授权（对应 Android `PermissionsScreen`）：读各项状态；没问过就弹系统询问，问过了就打开系统设置。
 * 回到前台时重新读一遍（用户可能刚在系统设置里改过）。
 */
@MainActor
@Observable
final class PermissionsModel: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var statuses: [AppPermission: PermissionStatus] = [:]

    @ObservationIgnored private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func refresh() async {
        statuses[.location] = switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        statuses[.notifications] = switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        statuses[.camera] = Self.status(AVCaptureDevice.authorizationStatus(for: .video))
        statuses[.photos] = switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        statuses[.microphone] = switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .undetermined: .notDetermined
        default: .denied
        }
    }

    func tap(_ permission: AppPermission) async {
        guard statuses[permission] == .notDetermined else {
            await UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            return
        }
        switch permission {
        case .location:
            locationManager.requestWhenInUseAuthorization()
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .photos:
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        }
        await refresh()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { await self.refresh() }
    }

    private static func status(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
