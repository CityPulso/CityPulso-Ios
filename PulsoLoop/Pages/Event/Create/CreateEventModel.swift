import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 刚发布、等发起人选「发帖」还是「去看看」的活动。 */
struct CreatedEventPrompt: Hashable, Sendable {
    let sport: LoopSport
    let eventId: String
}

/**
 * 发起活动向导（Android `EventCreateViewModel`，对齐 WEB SessionCreate 四步）：选运动 → 活动信息 / 时间地点 /
 * 活动设置 / 预览并发布 → 提交。照片选中就上传，发布时只带图片 id；装备要求随运动给默认值。
 */
@MainActor
@Observable
final class CreateEventModel {
    private(set) var draft = CreateDraft()
    private(set) var step = CreateStep.sport
    private(set) var formError: CreateFormError?
    private(set) var submitError: String?
    /** The publish button's phase: the post prompt comes up after its tick. */
    let publish = SubmitAction()
    var isSubmitting: Bool { publish.phase.busy }
    private(set) var nearbyBuildings: [BuildingItem] = []
    private(set) var profileReady = false
    private(set) var isPulser = false
    /** 选中照片的原始数据：上传中 / 失败时用它显示和重传（不进草稿）。 */
    private(set) var photoData: [String: Data] = [:]
    @ObservationIgnored private var photoMimeTypes: [String: String] = [:]
    var createdEvent: CreatedEventPrompt?
    var draftPrompt = false
    var leavePrompt = false

    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.eventCreateDraftStore) private var draftStore
    @ObservationIgnored @Injected(\.buildingService) private var buildingService
    @ObservationIgnored @Injected(\.assetRepository) private var assets
    @ObservationIgnored @Injected(\.nearbyQueryLocationStore) private var queryLocation
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let services = Container.shared.loopSportServices()
    /** 上次存的（或进来时找到的）草稿；离开时内容和它不一样才问要不要存。 */
    @ObservationIgnored private var savedDraft: CreateDraft?

    init() {
        if let stored = draftStore.draft, stored.sport?.available == true {
            savedDraft = stored
            draftPrompt = true
        }
    }

    var hasUnsavedContent: Bool { draft.hasContent && draft.forDraft != savedDraft }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        for await info in profileStore.current.values() {
            profileReady = true
            isPulser = info?.isPulser == true
        }
    }

    /** 表单上的改动统一走这里；提交中不改。 */
    func update(_ transform: (inout CreateDraft) -> Void) {
        guard !isSubmitting else { return }
        transform(&draft)
        submitError = nil
        formError = nil
    }

    /* ------------------------------ 返回 / 草稿 ------------------------------ */

    /** 返回：先退一步，再回到选运动，最后离开页面（返回 true 表示可以关页面）。 */
    func back() -> Bool {
        guard !isSubmitting else { return false }
        if step == .form, draft.wizardStep != CreateWizardStep.allCases.first {
            previousStep()
            return false
        }
        if step == .form {
            backToSportPick()
            return false
        }
        return leave()
    }

    /** 离开前，有没存的内容就先问要不要存草稿；返回 true 表示直接离开。 */
    func leave() -> Bool {
        guard !isSubmitting else { return false }
        if hasUnsavedContent {
            leavePrompt = true
            return false
        }
        return true
    }

    func saveDraft() {
        let snapshot = draft.forDraft
        guard snapshot.sport != nil else { return }
        draftStore.save(snapshot)
        savedDraft = snapshot
        PulsoMessageCenter.shared.success("create_draft_saved")
    }

    /** 「继续编辑」：用草稿填回表单，停在离开时那一步。 */
    func restoreDraft() {
        guard let saved = savedDraft else { return }
        draft = saved
        step = .form
        draftPrompt = false
    }

    /** 「重新开始」：删掉草稿，表单保持空白。 */
    func discardDraft() {
        savedDraft = nil
        draftPrompt = false
        draftStore.clear()
    }

    func saveDraftAndLeave() {
        leavePrompt = false
        saveDraft()
    }

    /* ------------------------------ 运动 / 步骤 ------------------------------ */

    /** 选运动；装备默认值由页面按发起人的语言给出。同一运动再选一次保留已填的装备。 */
    func selectSport(_ sport: LoopSport, defaultEquipment: [EquipmentDraft]) {
        guard sport.available, !isSubmitting else { return }
        let keepsEquipment = draft.sport == sport && !draft.equipment.isEmpty
        draft.sport = sport
        draft.wizardStep = .basics
        if !keepsEquipment { draft.equipment = defaultEquipment }
        if let cap = draft.optionsCapacity { draft = draft.withCapacity(cap) }
        step = .form
        submitError = nil
        formError = nil
    }

    func backToSportPick() {
        step = .sport
        submitError = nil
        formError = nil
    }

    func nextStep() {
        guard !isSubmitting else { return }
        if let error = draft.validationError(draft.wizardStep) {
            formError = error
            return
        }
        let steps = CreateWizardStep.allCases
        if let index = steps.firstIndex(of: draft.wizardStep), index + 1 < steps.count {
            draft.wizardStep = steps[index + 1]
        }
        submitError = nil
        formError = nil
    }

    func previousStep() {
        guard !isSubmitting else { return }
        let steps = CreateWizardStep.allCases
        if let index = steps.firstIndex(of: draft.wizardStep), index > 0 {
            draft.wizardStep = steps[index - 1]
        }
        submitError = nil
        formError = nil
    }

    /** 往后跳会检查中间每一步，发布步绕不过没填好的步骤。 */
    func goToStep(_ target: CreateWizardStep) {
        guard !isSubmitting else { return }
        let steps = CreateWizardStep.allCases
        let current = steps.firstIndex(of: draft.wizardStep) ?? 0
        let targetIndex = steps.firstIndex(of: target) ?? 0
        if targetIndex > current {
            for step in steps[..<targetIndex] {
                if let error = draft.validationError(step) {
                    draft.wizardStep = step
                    formError = error
                    return
                }
            }
        }
        draft.wizardStep = target
        submitError = nil
        formError = nil
    }

    /* ------------------------------ 地点 ------------------------------ */

    /** 用选点页定下的位置填地点，再找附近的场馆建筑自动关联最近的一个（失败就不关联）。 */
    func applyPickedLocation() async {
        guard let location = queryLocation.current else { return }
        update {
            $0.latitude = String(location.point.latitude)
            $0.longitude = String(location.point.longitude)
            $0.address = location.label
            $0.buildingId = nil
        }
        nearbyBuildings = []
        let nearby = (try? await buildingService.listNearbyBuildings(
            lat: location.point.latitude,
            lng: location.point.longitude,
            radiusM: buildingAutoLinkRadiusM,
            buildingTypes: BuildingType.loop.map(\.rawValue),
            limit: 5
        ))?.items ?? []
        nearbyBuildings = nearby
        if let closest = nearby.first {
            link(closest)
        }
    }

    func link(_ building: BuildingItem) {
        update {
            $0.buildingId = building.id
            $0.venueName = building.name
            if !building.address.isEmpty { $0.address = building.address }
            $0.latitude = String(building.locationLat)
            $0.longitude = String(building.locationLng)
        }
    }

    func unlinkBuilding() {
        update { $0.buildingId = nil }
    }

    /* ------------------------------ 照片 ------------------------------ */

    /** 加最多 [eventPhotosMax] 张照片，每张选中就开始上传。 */
    func addPhotos(_ picked: [(data: Data, mimeType: String)]) {
        guard !isSubmitting, !picked.isEmpty else { return }
        let room = eventPhotosMax - draft.photos.count
        guard room > 0 else {
            PulsoMessageCenter.shared.error(text: localizedFormat("create_photo_limit", eventPhotosMax))
            return
        }
        if picked.count > room {
            PulsoMessageCenter.shared.error(text: localizedFormat("create_photo_limit", eventPhotosMax))
        }
        for photo in picked.prefix(room) {
            let localId = UUID().uuidString
            photoData[localId] = photo.data
            photoMimeTypes[localId] = photo.mimeType
            draft.photos.append(EventPhotoDraft(localId: localId))
            formError = nil
            upload(localId, data: photo.data, mimeType: photo.mimeType)
        }
    }

    func retryPhoto(_ photo: EventPhotoDraft) {
        guard let data = photoData[photo.localId] else { return }
        setPhoto(photo.localId) { $0.status = .uploading }
        upload(photo.localId, data: data, mimeType: photoMimeTypes[photo.localId] ?? "image/jpeg")
    }

    func removePhoto(_ photo: EventPhotoDraft) {
        update { $0.photos.removeAll { $0.localId == photo.localId } }
        photoData[photo.localId] = nil
        photoMimeTypes[photo.localId] = nil
    }

    /** 挪到最前面：第一张是封面。 */
    func setCover(_ photo: EventPhotoDraft) {
        update { draft in
            draft.photos.removeAll { $0.localId == photo.localId }
            draft.photos.insert(photo, at: 0)
        }
    }

    private func upload(_ localId: String, data: Data, mimeType: String) {
        guard let sport = draft.sport else { return }
        let assets = assets
        Task {
            do {
                let ext = mimeType == "image/png" ? "png" : "jpg"
                let imageId = try await assets.uploadImage(data, fileName: "photo.\(ext)", mimeType: mimeType, category: .fromWire(sport.rawValue))
                setPhoto(localId) {
                    $0.imageId = imageId
                    $0.status = .ready
                }
            } catch {
                setPhoto(localId) { $0.status = .failed }
                PulsoMessageCenter.shared.error(error, fallback: "create_photo_upload_failed")
            }
        }
    }

    private func setPhoto(_ localId: String, _ change: (inout EventPhotoDraft) -> Void) {
        guard let index = draft.photos.firstIndex(where: { $0.localId == localId }) else { return }
        change(&draft.photos[index])
    }

    /* ------------------------------ 字段 ------------------------------ */

    func setCourtCount(_ value: String) {
        update {
            $0.courtCount = value
            $0 = $0.syncedCapacity()
        }
    }

    func setPlayersPerCourt(_ value: String) {
        update {
            $0.playersPerCourt = value
            $0 = $0.syncedCapacity()
        }
    }

    func setCapacity(_ value: String) {
        update {
            $0.capacity = value
            $0.capacityTouched = true
        }
    }

    /** 各运动自己的选项算出的名额预填名额，直到发起人手改。 */
    func setOptions(_ change: (inout CreateDraft) -> Void) {
        update {
            change(&$0)
            if let cap = $0.optionsCapacity { $0 = $0.withCapacity(cap) }
        }
    }

    /* ------------------------------ 提交 ------------------------------ */

    func submit() async {
        guard let sport = draft.sport, !isSubmitting, isPulser, sport.available else { return }
        for step in CreateWizardStep.allCases {
            if let error = draft.validationError(step) {
                draft.wizardStep = step
                formError = error
                return
            }
        }
        guard let latitude = Double(draft.latitude), let longitude = Double(draft.longitude), let service = services[sport] else { return }
        submitError = nil
        formError = nil
        await publish.run({
            try await service.createEvent(draft, buildingId: draft.buildingId, latitude: latitude, longitude: longitude)
        }, onFailure: { error in
            self.submitError = UiError(error).text(fallback: String(localized: "create_flow_error_submit"))
        }, afterSuccess: { eventId in
            self.savedDraft = nil
            self.draftStore.clear()
            self.draft = CreateDraft()
            self.photoData = [:]
            self.photoMimeTypes = [:]
            self.nearbyBuildings = []
            self.step = .sport
            self.createdEvent = CreatedEventPrompt(sport: sport, eventId: eventId)
        })
    }
}
