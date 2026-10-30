import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 名字和备注的长度上限（WEB `VENUE_LIMITS.nameMax` / `instructionsMax`）。 */
let placeNameMax = 200
let placeNoteMax = 2000
/** 联系方式上限（WEB `VENUE_LIMITS.contactEmailMax` / `contactPhoneMax`）。 */
let placeEmailMax = 254
let placePhoneMax = 32
/** 一个地点最多几张照片；第一张是地图上的封面。 */
let placePhotosMax = 12

/** 逐项校验（WEB `placeRequestSchema`）；nil 表示没问题。 */
struct MarkPlaceErrors: Equatable {
    var type: String?
    var name: String?
    var address: String?
    var photos: String?
    var note: String?
    var email: String?
    var phone: String?

    var any: Bool { [type, name, address, photos, note, email, phone].contains { $0 != nil } }
}

/**
 * 标记地图上缺的球馆、户外场地或公园（Android `MarkPlaceViewModel`，WEB `MarkPlacePage`）。照片选中就上传；
 * 监管员审核通过后它会出现在地图上。带 [requestId] 时是把被拒的那条改了再提交。
 */
@MainActor
@Observable
final class MarkPlaceModel {
    let requestId: String?

    /** 在读要重新提交的那条。 */
    private(set) var loading: Bool
    /** 要重新提交的那条找不到，或者不是被拒状态。 */
    private(set) var unavailable = false
    var resubmitting: Bool { requestId != nil }
    private(set) var reviewNote: String?
    var type: BuildingType?
    var name = "" { didSet { if name.count > placeNameMax { name = String(name.prefix(placeNameMax)) } } }
    private(set) var latitude: Double?
    private(set) var longitude: Double?
    private(set) var address = ""
    var note = "" { didSet { if note.count > placeNoteMax { note = String(note.prefix(placeNoteMax)) } } }
    var email = "" { didSet { if email.count > placeEmailMax { email = String(email.prefix(placeEmailMax)) } } }
    var phone = "" { didSet { if phone.count > placePhoneMax { phone = String(phone.prefix(placePhoneMax)) } } }
    /** 电话是可选的附加项，点了才显示（以前填过的直接显示）。 */
    private(set) var showPhone = false
    /** 位置预览用的地图样式（球友的地图偏好）。 */
    private(set) var map = ResolvedMapPreference()
    private(set) var photos: [EventPhotoDraft] = []
    /** 本地选中的照片数据：上传中 / 失败时显示它，重试也用它。 */
    private(set) var photoData: [String: Data] = [:]
    @ObservationIgnored private var photoMimeTypes: [String: String] = [:]
    private(set) var submitting = false
    /** 第一次提交后才显示各项错误。 */
    private(set) var showErrors = false

    @ObservationIgnored @Injected(\.placeRequestService) private var places
    @ObservationIgnored @Injected(\.locationService) private var locationService
    @ObservationIgnored @Injected(\.assetRepository) private var assets
    @ObservationIgnored @Injected(\.nearbyQueryLocationStore) private var nearbyLocation
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.preferenceService) private var preferenceService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    /** 账号的主邮箱，新地点的联系邮箱默认用它。 */
    private var primaryEmail: String { profileStore.current.value?.primaryEmail ?? "" }

    var photosUploading: Bool { photos.contains { $0.status == .uploading } }
    var placeTypes: [BuildingType] { BuildingType.loop }

    init(requestId: String?, latitude: Double? = nil, longitude: Double? = nil) {
        self.requestId = requestId
        loading = requestId != nil
        if requestId == nil {
            email = primaryEmail
            // 只有一种地点类型时不用选：直接选好。
            type = BuildingType.loop.count == 1 ? BuildingType.loop.first : nil
            let lat = latitude ?? nearbyLocation.current?.point.latitude
            let lng = longitude ?? nearbyLocation.current?.point.longitude
            if let lat, let lng {
                let label = latitude == nil ? nearbyLocation.current?.label : nil
                pickLocation(lat, lng, label: label?.isEmpty == false ? label : nil)
            }
        }
    }

    func observe() async {
        await concurrently([
            {
                for await preference in self.preferenceService.preference.values() {
                    self.map = preference.map
                }
            },
            {
                guard let requestId = self.requestId else { return }
                await self.loadRejected(requestId)
            },
        ])
    }

    private func loadRejected(_ requestId: String) async {
        guard let request = try? await places.get(requestId), PlaceRequestStatus.fromWire(request.status) == .rejected else {
            loading = false
            unavailable = true
            return
        }
        loading = false
        reviewNote = request.reviewNote
        type = BuildingType.loop.first { $0.rawValue == request.proposedBuildingType }
        name = request.proposedName ?? ""
        latitude = request.proposedLocationLat
        longitude = request.proposedLocationLng
        address = request.proposedAddress ?? ""
        note = request.evidenceNote ?? ""
        email = request.contactEmail.flatMap { $0.isEmpty ? nil : $0 } ?? primaryEmail
        phone = request.contactPhone ?? ""
        showPhone = !(request.contactPhone ?? "").isEmpty
        photos = request.imageIds.prefix(placePhotosMax).map { EventPhotoDraft(localId: $0, imageId: $0, status: .ready) }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func addPhone() {
        showPhone = true
    }

    func removePhone() {
        phone = ""
        showPhone = false
    }

    /** 把针放在 [lat]/[lng]；没有 [label] 时用反查的地址。 */
    func pickLocation(_ lat: Double, _ lng: Double, label: String?) {
        latitude = lat
        longitude = lng
        address = label ?? ""
        guard label?.isEmpty ?? true else { return }
        let service = locationService
        Task { [weak self] in
            guard let item = try? await service.reverseGeocode(lat: lat, lng: lng).resultItems?.first else { return }
            guard let found = item.address?.label ?? item.title, let self, self.latitude == lat, self.longitude == lng else { return }
            self.address = found
        }
    }

    /* ------------------------------ 照片 ------------------------------ */

    func addPhotos(_ picked: [(data: Data, mimeType: String)]) {
        guard !submitting, !picked.isEmpty else { return }
        let room = placePhotosMax - photos.count
        guard room > 0 else {
            PulsoMessageCenter.shared.error(text: localizedFormat("place_mark_photo_limit", placePhotosMax))
            return
        }
        for photo in picked.prefix(room) {
            let localId = UUID().uuidString
            photoData[localId] = photo.data
            photoMimeTypes[localId] = photo.mimeType
            photos.append(EventPhotoDraft(localId: localId))
            upload(localId, data: photo.data, mimeType: photo.mimeType)
        }
    }

    func retryPhoto(_ photo: EventPhotoDraft) {
        guard let data = photoData[photo.localId] else { return }
        setPhoto(photo.localId) { $0.status = .uploading }
        upload(photo.localId, data: data, mimeType: photoMimeTypes[photo.localId] ?? "image/jpeg")
    }

    func removePhoto(_ photo: EventPhotoDraft) {
        photos.removeAll { $0.localId == photo.localId }
        photoData[photo.localId] = nil
        photoMimeTypes[photo.localId] = nil
    }

    /** 第一张是地图上的封面。 */
    func setCover(_ photo: EventPhotoDraft) {
        photos.removeAll { $0.localId == photo.localId }
        photos.insert(photo, at: 0)
    }

    private func upload(_ localId: String, data: Data, mimeType: String) {
        let assets = assets
        Task {
            do {
                let ext = mimeType == "image/png" ? "png" : "jpg"
                let imageId = try await assets.uploadImage(data, fileName: "photo.\(ext)", mimeType: mimeType, category: .building)
                setPhoto(localId) {
                    $0.imageId = imageId
                    $0.status = .ready
                }
            } catch {
                setPhoto(localId) { $0.status = .failed }
                PulsoMessageCenter.shared.error(error, fallback: "place_mark_photo_failed")
            }
        }
    }

    private func setPhoto(_ localId: String, _ change: (inout EventPhotoDraft) -> Void) {
        guard let index = photos.firstIndex(where: { $0.localId == localId }) else { return }
        change(&photos[index])
    }

    /* ------------------------------ 校验与提交 ------------------------------ */

    var errors: MarkPlaceErrors {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        var errors = MarkPlaceErrors()
        if type == nil || !BuildingType.loop.contains(type!) { errors.type = String(localized: "place_mark_error_type") }
        if name.isEmpty {
            errors.name = String(localized: "place_mark_error_name")
        } else if name.count > placeNameMax {
            errors.name = localizedFormat("place_mark_error_name_long", placeNameMax)
        }
        if latitude == nil || longitude == nil || address.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.address = String(localized: "place_mark_error_location")
        }
        if !photos.contains(where: { $0.status == .ready }) { errors.photos = String(localized: "place_mark_error_photos") }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).count > placeNoteMax { errors.note = localizedFormat("place_mark_error_note_long", placeNoteMax) }
        if email.isEmpty {
            errors.email = String(localized: "place_mark_error_email_required")
        } else if email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil {
            errors.email = String(localized: "place_mark_error_email")
        }
        if phone.trimmingCharacters(in: .whitespaces).count > placePhoneMax { errors.phone = localizedFormat("place_mark_error_phone_long", placePhoneMax) }
        return errors
    }

    /** 提交成功返回 true（页面关掉）。 */
    func submit() async -> Bool {
        guard !submitting, !photosUploading else { return false }
        guard !errors.any, let type, let latitude, let longitude else {
            showErrors = true
            return false
        }
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = SubmitPlaceRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            buildingType: type.rawValue,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            locationLat: latitude,
            locationLng: longitude,
            imageIds: photos.compactMap { $0.status == .ready ? $0.imageId : nil },
            contactEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
            contactPhone: phone.isEmpty ? nil : phone,
            evidenceNote: note.isEmpty ? nil : note
        )
        submitting = true
        defer { submitting = false }
        do {
            try await places.submit(requestId, body)
            PulsoMessageCenter.shared.success("place_mark_sent")
            return true
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "place_mark_failed")
            return false
        }
    }
}
