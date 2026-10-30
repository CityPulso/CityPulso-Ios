import Foundation
import PulsoLinkCore
import PulsoLinkUI

/** 一场活动最多几张照片，第一张是封面（Android `EVENT_PHOTOS_MAX`，WEB `MAX_PHOTOS`）。 */
let activityPhotosMax = 6

/** 麻将规则文字的上限（WEB `MAHJONG_VARIANT_MAX_LENGTH`）。 */
let mahjongVariantMaxLength = 60

extension CreatePaymentMethodKind {
    /** 各活动类型 `<ActivityType>PaymentMethodKind` 的 wire 值（四种一样）。 */
    var wire: String {
        switch self {
        case .etransfer: "etransfer"
        case .wechat: "wechat"
        case .cash: "cash"
        case .stripe: "stripe"
        }
    }
}

/** 一张照片：本地选中的 id、上传确认后的图片 id（Android `ActivityPhotoDraft`；iOS 用 [localId] 代替 content uri）。 */
struct ActivityPhotoDraft: Codable, Hashable, Sendable, Identifiable {
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

/* ------------------------------ 表单 ------------------------------ */

/**
 * 整张发起表单，也是本地草稿（Android `CreateFormState` 里非 @Transient 的部分；界面状态在 [CreateActivityModel] 上）。
 */
struct CreateDraft: Codable, Hashable, Sendable {
    var activityType: NearActivityKind?
    var wizardStep = CreateWizardStep.basics
    var title = ""
    var description = ""
    /** 按显示顺序；第一张是封面。 */
    var photos: [ActivityPhotoDraft] = []
    var venueName = ""
    var address = ""
    var buildingId: String?
    var startsAt = ""
    var endsAt = ""
    var latitude = ""
    var longitude = ""
    /** 最少人数和名额从这种活动的默认范围开始（[NearActivityKind] 的默认值），发起人可以改。 */
    var minParticipants = ""
    var capacity = ""
    var waitlistCapacity = ""
    /** 只有麻将：规则的自由文字（WEB `MahjongForm`），快捷项会填进来。 */
    var mahjongVariant = ""
    var isFree = true
    var priceAmount = ""
    var paymentMethods: [CreatePaymentMethodDraft] = []
    var payeePaymentAccountId: String?
    var allowsFreeExit = false
    var freeExitHours = ExitDeadlineHours.h24
    /** 发布步上勾选这种活动的提示（[NearActivityKind.notice]）；只有「禁止赌博」必须勾。 */
    var noticeAcknowledged = false

    var acceptsStripe: Bool { !isFree && paymentMethods.contains { $0.method == .stripe } }
    var isUploadingPhotos: Bool { photos.contains { $0.status == .uploading } }
    var hasLocation: Bool { !latitude.isEmpty && !longitude.isEmpty }

    /** 填了值得留的东西，离开时才问要不要存草稿。 */
    var hasContent: Bool {
        activityType != nil && (!title.isEmpty || !description.isEmpty || !photos.isEmpty || !latitude.isEmpty || !startsAt.isEmpty)
    }

    /** 存进草稿的样子：只留已上传的照片（没传完的重启后没法续传）。 */
    var forDraft: CreateDraft {
        var copy = self
        copy.photos = photos.filter { $0.status == .ready }
        return copy
    }

    /** 选好类型时用它的默认人数预填（还没填过才填）。 */
    func withDefaults(for kind: NearActivityKind) -> CreateDraft {
        var copy = self
        copy.activityType = kind
        if minParticipants.isEmpty { copy.minParticipants = String(kind.defaultMinParticipants) }
        if capacity.isEmpty { copy.capacity = String(kind.defaultMaxParticipants) }
        if waitlistCapacity.isEmpty { copy.waitlistCapacity = String(kind.defaultMaxParticipants / 2) }
        return copy
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
            if let error = mahjongVariantError { return error }
            let min = Int(minParticipants) ?? 0
            if min < 1 { return CreateFormError(key: "create_flow_error_min_participants") }
            if (Int(capacity) ?? 0) < min { return CreateFormError(key: "create_flow_error_capacity_below_min", argument: .text(String(min))) }
            if (Int(waitlistCapacity) ?? -1) < 0 { return CreateFormError(key: "create_flow_error_waitlist_negative") }
            return (isFree ? nil : paymentError) ?? freeExitError(now: now)
        case .publish:
            if activityType?.notice == .noGambling, !noticeAcknowledged { return CreateFormError(key: "create_flow_error_notice") }
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

    /** 麻将要写规则（WEB `mahjongSteps`）：必填，最多 [mahjongVariantMaxLength] 个字。 */
    var mahjongVariantError: CreateFormError? {
        guard activityType == .mahjong else { return nil }
        let variant = mahjongVariant.trimmingCharacters(in: .whitespacesAndNewlines)
        if variant.isEmpty { return CreateFormError(key: "create_flow_error_mahjong_variant_required") }
        if variant.count > mahjongVariantMaxLength {
            return CreateFormError(key: "create_flow_error_mahjong_variant_too_long", argument: .text(String(mahjongVariantMaxLength)))
        }
        return nil
    }

    /** 封面必填，每张照片都要传完。 */
    private var photosError: CreateFormError? {
        if photos.isEmpty { return CreateFormError(key: "create_photo_cover_required") }
        if photos.contains(where: { $0.status == .uploading }) { return CreateFormError(key: "create_photo_still_uploading") }
        if photos.contains(where: { $0.status == .failed }) { return CreateFormError(key: "create_photo_has_failed") }
        return nil
    }

    /** 对齐 WEB `boardGameSteps.ts` / API `validateNewActivityParams`：0 < 免费退出小时数 < 距开始小时数。 */
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

    var minParticipantsValue: Int { Int(minParticipants) ?? 1 }
    var capacityValue: Int { Int(capacity) ?? minParticipantsValue }
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

/** 快捷时长的结束时间（Android `ActivityDurationPreset.endsAt`）：几小时后、当天 23:59、加一天。 */
func endsAt(_ preset: ActivityDurationPreset, start: Date, calendar: Calendar = .current) -> Date {
    switch preset {
    case .hours2: start.addingTimeInterval(2 * 3600)
    case .hours4: start.addingTimeInterval(4 * 3600)
    case .hours6: start.addingTimeInterval(6 * 3600)
    case .sameDay:
        calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start).flatMap { $0 > start ? $0 : nil }
            ?? calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    case .plusOneDay: calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }
}

/** 当前起止对应哪个快捷时长；自定义结束时间返回 nil。 */
func matchingActivityDuration(start: Date, end: Date) -> ActivityDurationPreset? {
    let endMinute = floor(end.timeIntervalSince1970 / 60)
    return ActivityDurationPreset.allCases.first { floor(endsAt($0, start: start).timeIntervalSince1970 / 60) == endMinute }
}

/** 改开始时间：原来的结束刚好是某个快捷时长就沿用，否则默认 2 小时。 */
func endsAtAfterStartChange(previousStart: String, previousEnd: String, nextStart: Date) -> Date {
    let preset = DateTimeFormatters.parseInstant(previousStart).flatMap { start in
        DateTimeFormatters.parseInstant(previousEnd).flatMap { matchingActivityDuration(start: start, end: $0) }
    } ?? .hours2
    return endsAt(preset, start: nextStart)
}

/** 发给后端的 ISO 时间（和 Android `Instant.toString()` 一样带 Z）。 */
func isoInstant(_ date: Date) -> String {
    date.formatted(.iso8601)
}
