import Foundation
import PulsoLinkCore

/** 一场活动最多几张照片，第一张是封面（Android `EVENT_PHOTOS_MAX`，WEB `MAX_PHOTOS`）。 */
let eventPhotosMax = 6

extension CreatePaymentMethodKind {
    /** 各运动 `<Sport>PaymentMethodKind` 的 wire 值（四种一样）。 */
    var wire: String {
        switch self {
        case .etransfer: "etransfer"
        case .wechat: "wechat"
        case .cash: "cash"
        case .stripe: "stripe"
        }
    }
}

/** 活动上的一条装备要求：图标 key 和发起人看到的文字（Android `EquipmentDraft`）。 */
struct EquipmentDraft: Codable, Hashable, Sendable {
    var icon: String
    var name: String
}

/** 一张照片：本地选中的 id、上传确认后的图片 id（Android `EventPhotoDraft`；iOS 用 [localId] 代替 content uri）。 */
struct EventPhotoDraft: Codable, Hashable, Sendable, Identifiable {
    var localId: String
    var imageId: String?
    var status: PhotoUploadStatus = .uploading

    var id: String { localId }
}

/** 向导里的一种收款方式；[account] 是发起人填的转账 / 微信账户（Android `CreatePaymentMethodDraft`）。 */
struct CreatePaymentMethodDraft: Codable, Hashable, Sendable {
    var method: CreatePaymentMethodKind
    var account = ""
}

/** 向导校验 / 提交错误：文案 key + 参数（Android `CreateFormError`）。 */
struct CreateFormError: Hashable, Sendable {
    enum Argument: Hashable, Sendable {
        case number(Int)
        case text(String)
    }

    let key: String
    var argument: Argument?

    var text: String {
        switch argument {
        case nil: localizedFormat(key)
        case let .number(value): localizedFormat(key, value)
        case let .text(value): localizedFormat(key, value)
        }
    }
}

/* ------------------------------ 各运动自己的选项 ------------------------------ */

struct BasketballOptionsDraft: Codable, Hashable, Sendable {
    var courtCount = "1"
    var basketballFormat = BasketballFormat.fallback
    var eligibilityDivision = EligibilityDivision.fallback

    var courts: Int { Int(courtCount) ?? 1 }
    var isValid: Bool { (1 ... 999).contains(Int(courtCount) ?? -1) }
    var capacity: Int { courts * (basketballFormat == .halfCourt ? 6 : 10) }
}

struct FootballOptionsDraft: Codable, Hashable, Sendable {
    var footballFormat = FootballFormat.fallback
    var pitchSurface = PitchSurface.fallback
    var eligibilityDivision = EligibilityDivision.fallback

    var isValid: Bool { true }
    var capacity: Int {
        switch footballFormat {
        case .fiveASide: 10
        case .sevenASide: 14
        case .elevenASide: 22
        }
    }
}

struct BaseballOptionsDraft: Codable, Hashable, Sendable {
    var baseballVariant = BaseballVariant.fallback
    var innings = "7"

    var inningCount: Int { Int(innings) ?? 7 }
    var isValid: Bool { (5 ... 9).contains(Int(innings) ?? -1) }
    var capacity: Int { 18 }
}

struct GolfOptionsDraft: Codable, Hashable, Sendable {
    var golfHoles = GolfHoles.fallback
    var groupCount = "1"
    var playersPerGroup = "4"

    var groups: Int { Int(groupCount) ?? 1 }
    var playersInGroup: Int { Int(playersPerGroup) ?? 4 }
    var isValid: Bool { (1 ... 999).contains(Int(groupCount) ?? -1) && (2 ... 4).contains(Int(playersPerGroup) ?? -1) }
    var capacity: Int { groups * playersInGroup }
}

struct HikingOptionsDraft: Codable, Hashable, Sendable {
    var hikingDifficulty = HikingDifficulty.fallback
    var distanceKm = "5"
    var elevationGainM = ""

    var distance: Double { Double(distanceKm) ?? 0 }
    var elevationGain: Int? { Int(elevationGainM) }
    var isValid: Bool {
        (0.1 ... 9999.9).contains(Double(distanceKm) ?? -1) && (elevationGainM.isEmpty || (0 ... 9999).contains(Int(elevationGainM) ?? -1))
    }

    var capacity: Int { 12 }
}

struct FishingOptionsDraft: Codable, Hashable, Sendable {
    var fishingMethod = FishingMethod.fallback
    var catchPolicy = CatchPolicy.fallback
    var requiresLicense = true

    var isValid: Bool { true }
    var capacity: Int { 6 }
}

struct SkiOptionsDraft: Codable, Hashable, Sendable {
    var skiDiscipline = SkiDiscipline.fallback
    var skiSkillLevel = SkiSkillLevel.fallback
    var includesLiftTicket = false

    var isValid: Bool { true }
    var capacity: Int { 8 }
}

struct TableTennisOptionsDraft: Codable, Hashable, Sendable {
    var tableCount = "1"
    var playersPerTable = "4"
    var matchFormat = MatchFormat.fallback
    var eligibilityDivision = EligibilityDivision.fallback

    var tables: Int { Int(tableCount) ?? 1 }
    var playersAtTable: Int { Int(playersPerTable) ?? 4 }
    var isValid: Bool { (1 ... 999).contains(Int(tableCount) ?? -1) && (1 ... 999).contains(Int(playersPerTable) ?? -1) }
    var capacity: Int { tables * playersAtTable }
}

/* ------------------------------ 表单 ------------------------------ */

/**
 * 整张发起表单，也是本地草稿（Android `CreateFormState` 里非 @Transient 的部分；界面状态在 [CreateEventModel] 上）。
 */
struct CreateDraft: Codable, Hashable, Sendable {
    var sport: LoopSport?
    var wizardStep = CreateWizardStep.basics
    var title = ""
    var description = ""
    /** 按显示顺序；第一张是封面。 */
    var photos: [EventPhotoDraft] = []
    var venueName = ""
    var address = ""
    var buildingId: String?
    var startsAt = ""
    var endsAt = ""
    var latitude = ""
    var longitude = ""
    var courtCount = "2"
    var playersPerCourt = "4"
    var capacity = "8"
    var waitlistCapacity = "4"
    /** 发起人手动改过名额后，场地数 × 每场人数不再覆盖它。 */
    var capacityTouched = false
    var equipment: [EquipmentDraft] = []
    var isFree = true
    var priceAmount = ""
    var paymentMethods: [CreatePaymentMethodDraft] = []
    var payeePaymentAccountId: String?
    var eligibilityDivision = EligibilityDivision.fallback
    var matchFormat = MatchFormat.fallback
    var basketballOptions = BasketballOptionsDraft()
    var footballOptions = FootballOptionsDraft()
    var baseballOptions = BaseballOptionsDraft()
    var golfOptions = GolfOptionsDraft()
    var hikingOptions = HikingOptionsDraft()
    var fishingOptions = FishingOptionsDraft()
    var skiOptions = SkiOptionsDraft()
    var tableTennisOptions = TableTennisOptionsDraft()
    var allowsFreeExit = false
    var freeExitHours = ExitDeadlineHours.h24

    var acceptsStripe: Bool { !isFree && paymentMethods.contains { $0.method == .stripe } }
    var isUploadingPhotos: Bool { photos.contains { $0.status == .uploading } }
    var hasLocation: Bool { !latitude.isEmpty && !longitude.isEmpty }

    /** 填了值得留的东西，离开时才问要不要存草稿。 */
    var hasContent: Bool {
        sport != nil && (!title.isEmpty || !description.isEmpty || !photos.isEmpty || !latitude.isEmpty || !startsAt.isEmpty)
    }

    /** 存进草稿的样子：只留已上传的照片（没传完的重启后没法续传）。 */
    var forDraft: CreateDraft {
        var copy = self
        copy.photos = photos.filter { $0.status == .ready }
        return copy
    }

    /** 选好的运动按自己的选项算出的名额；球拍类按场地数 × 每场人数算，这里返回 nil。 */
    var optionsCapacity: Int? {
        switch sport {
        case .badminton, .tennis, .pickleball, nil: nil
        case .basketball: basketballOptions.capacity
        case .football: footballOptions.capacity
        case .baseball: baseballOptions.capacity
        case .golf: golfOptions.capacity
        case .hiking: hikingOptions.capacity
        case .fishing: fishingOptions.capacity
        case .ski: skiOptions.capacity
        case .tableTennis: tableTennisOptions.capacity
        }
    }

    var sportOptionsValid: Bool {
        switch sport {
        case .badminton, .tennis, .pickleball, nil: [courtCount, playersPerCourt].allSatisfy { (Int($0) ?? 0) > 0 }
        case .basketball: basketballOptions.isValid
        case .football: footballOptions.isValid
        case .baseball: baseballOptions.isValid
        case .golf: golfOptions.isValid
        case .hiking: hikingOptions.isValid
        case .fishing: fishingOptions.isValid
        case .ski: skiOptions.isValid
        case .tableTennis: tableTennisOptions.isValid
        }
    }

    /** 没手改过名额时，用 [cap] 预填名额和一半的候补。 */
    func withCapacity(_ cap: Int) -> CreateDraft {
        guard !capacityTouched, cap > 0 else { return self }
        var copy = self
        copy.capacity = String(cap)
        copy.waitlistCapacity = String(cap / 2)
        return copy
    }

    /** 场地数 × 每场人数预填名额（和一半的候补），直到发起人手改名额。 */
    func syncedCapacity() -> CreateDraft {
        guard !capacityTouched, let courts = Int(courtCount), let players = Int(playersPerCourt) else { return self }
        return withCapacity(max(1, courts) * max(1, players))
    }

    /* ------------------------------ 校验 ------------------------------ */

    /** 提交时也用，所以从发布步跳回去也绕不过校验。 */
    func validationError(_ step: CreateWizardStep, now: Date = .now) -> CreateFormError? {
        switch step {
        case .basics:
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return CreateFormError(key: "create_flow_error_title") }
            return photosError
        case .whenWhere:
            return whenWhereError(now: now)
        case .settings:
            if !sportOptionsValid || (Int(capacity) ?? 0) <= 0 || (Int(waitlistCapacity) ?? -1) < 0 {
                return CreateFormError(key: "create_flow_error_capacity")
            }
            if equipment.count > eventEquipmentMax {
                return CreateFormError(key: "create_equipment_limit", argument: .number(eventEquipmentMax))
            }
            return (isFree ? nil : paymentError) ?? freeExitError(now: now)
        case .publish:
            return nil
        }
    }

    private func whenWhereError(now: Date) -> CreateFormError? {
        guard let start = DateTimeFormatters.parseInstant(startsAt), let end = DateTimeFormatters.parseInstant(endsAt),
              start > now, end > start
        else { return CreateFormError(key: "create_flow_error_time") }
        guard let lat = Double(latitude), let lng = Double(longitude), lat.isFinite, lng.isFinite,
              (-90 ... 90).contains(lat), (-180 ... 180).contains(lng)
        else { return CreateFormError(key: "create_flow_error_location") }
        return nil
    }

    /** 封面必填，每张照片都要传完。 */
    private var photosError: CreateFormError? {
        if photos.isEmpty { return CreateFormError(key: "create_photo_cover_required") }
        if photos.contains(where: { $0.status == .uploading }) { return CreateFormError(key: "create_photo_still_uploading") }
        if photos.contains(where: { $0.status == .failed }) { return CreateFormError(key: "create_photo_has_failed") }
        return nil
    }

    /** 对齐 WEB `badmintonSteps.ts` / API `validateNewEventParams`：0 < 免费退出小时数 < 距开始小时数。 */
    private func freeExitError(now: Date) -> CreateFormError? {
        guard allowsFreeExit, let start = DateTimeFormatters.parseInstant(startsAt) else { return nil }
        let hoursUntil = start.timeIntervalSince(now) / 3600
        let hours = Double(freeExitHours.hours)
        if hours > 0, hours < hoursUntil { return nil }
        return CreateFormError(key: "create_flow_error_free_exit", argument: .text(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), hoursUntil)))
    }

    /** 对齐 WEB pricing 校验：价格 → 至少一种方式 → 各方式的账户 / 收款账户 / Stripe 最低价。 */
    private var paymentError: CreateFormError? {
        guard let price = Double(priceAmount), price.isFinite, price > 0 else { return CreateFormError(key: "create_flow_error_price") }
        if paymentMethods.isEmpty { return CreateFormError(key: "create_payment_error_required") }
        for entry in paymentMethods {
            let account = entry.account.trimmingCharacters(in: .whitespacesAndNewlines)
            switch entry.method {
            case .etransfer where account.isEmpty: return CreateFormError(key: "create_payment_error_etransfer_account")
            case .wechat where account.isEmpty: return CreateFormError(key: "create_payment_error_wechat_account")
            case .stripe:
                if payeePaymentAccountId == nil { return CreateFormError(key: "create_payment_error_payment_account") }
                if price < stripeMinAmount {
                    return CreateFormError(key: "create_payment_error_stripe_min", argument: .text(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), stripeMinAmount)))
                }
            default: break
            }
        }
        return nil
    }

    /* ------------------------------ 提交用的公共字段 ------------------------------ */

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDescription: String? { description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }

    /** 关联了建筑就不带自填的地点、地址和坐标（后端用建筑的）。 */
    func place(buildingId: String?) -> (venueName: String?, address: String?) {
        guard buildingId == nil else { return (nil, nil) }
        return (venueName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
    }

    var capacityValue: Int { Int(capacity) ?? 4 }
    var waitlistValue: Int { Int(waitlistCapacity) ?? 0 }
    var priceValue: Double? { isFree ? nil : Double(priceAmount) }
    var payeeValue: String? { acceptsStripe ? payeePaymentAccountId : nil }
    var freeExitHoursValue: Int? { allowsFreeExit ? freeExitHours.hours : nil }
    /** 已上传照片的 (图片 id, 顺序)。 */
    var imageInputs: [(imageId: String, sortOrder: Int)] {
        photos.enumerated().compactMap { index, photo in photo.imageId.map { ($0, index) } }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/* ------------------------------ 时长 ------------------------------ */

/** 快捷时长的显示：1.5 还是 1.5，2.0 显示成 2。 */
func durationHoursText(_ minutes: Int) -> String {
    minutes % 60 == 0 ? String(minutes / 60) : String(Double(minutes) / 60)
}

func endsAt(after start: Date, minutes: Int) -> Date {
    start.addingTimeInterval(Double(minutes) * 60)
}

/** 当前起止对应这项运动的哪个快捷时长；自定义结束时间返回 nil。 */
func matchingDurationMinutes(start: Date, end: Date, sport: LoopSport) -> Int? {
    let endMinute = floor(end.timeIntervalSince1970 / 60)
    return sport.durationPresetsMinutes.first { floor(endsAt(after: start, minutes: $0).timeIntervalSince1970 / 60) == endMinute }
}

/** 改开始时间：原来的结束刚好是某个快捷时长就沿用，否则用这项运动的默认时长。 */
func endsAtAfterStartChange(previousStart: String, previousEnd: String, nextStart: Date, sport: LoopSport) -> Date {
    let minutes = DateTimeFormatters.parseInstant(previousStart).flatMap { start in
        DateTimeFormatters.parseInstant(previousEnd).flatMap { matchingDurationMinutes(start: start, end: $0, sport: sport) }
    } ?? sport.defaultDurationMinutes
    return endsAt(after: nextStart, minutes: minutes)
}

/** 发给后端的 ISO 时间（和 Android `Instant.toString()` 一样带 Z）。 */
func isoInstant(_ date: Date) -> String {
    date.formatted(.iso8601)
}
