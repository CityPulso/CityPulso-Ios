import Foundation

/**
 * 支付域门面（对应 Android `PaymentsService` + `PaymentsQueryStore`）：收款账户和付款卡的查询与修改，失效在这一层发齐。
 * 两个列表都挂在账号上（key = 账号 id），与当前身份无关。
 */
public final class PaymentsService: LogoutClearable {
    public let paymentAccounts: MemoryQuery<String, ListWithTotal<PaymentAccountItem>>
    public let paymentMethods: MemoryQuery<String, ListWithTotal<PaymentMethodItem>>

    private let api: PaymentsAPI
    private let publicAPI: PaymentsPublicAPI
    private let bus: PaymentsEventBus
    private let location: LocationService

    public init(api: PaymentsAPI, publicAPI: PaymentsPublicAPI, bus: PaymentsEventBus, location: LocationService) {
        self.api = api
        self.publicAPI = publicAPI
        self.bus = bus
        self.location = location
        let invalidates: @Sendable () -> AsyncStream<Void> = { bus.signals { _ in true } }
        paymentAccounts = MemoryQuery(invalidates: invalidates) { _ in
            try await api.listPaymentAccounts(PaymentAccountListRequest()).dataOrThrow("ListPaymentAccounts")
        }
        paymentMethods = MemoryQuery(invalidates: invalidates) { _ in
            try await api.listPaymentMethods().dataOrThrow("ListPaymentMethods")
        }
    }

    /* ------------------------------ 收款账户 ------------------------------ */

    public func createPaymentAccount(_ body: CreatePaymentAccountRequest, idempotencyKey: String) async throws -> PaymentAccountItem {
        let account = try await api.createPaymentAccount(idempotencyKey: idempotencyKey, body).dataOrThrow("CreatePaymentAccount")
        invalidate()
        return account
    }

    public func createPaymentAccountOnboardingSession(paymentAccountId: String) async throws -> PaymentAccountOnboardingSession {
        try await api.createPaymentAccountOnboardingSession(paymentAccountId: paymentAccountId).dataOrThrow("CreatePaymentAccountOnboardingSession")
    }

    public func syncPaymentAccount(paymentAccountId: String) async throws -> PaymentAccountItem {
        let account = try await api.syncPaymentAccount(paymentAccountId: paymentAccountId).dataOrThrow("SyncPaymentAccount")
        invalidate()
        return account
    }

    /** 用商家资料（球馆名、电话、反查出的地址、经营说明、MCC）预填 Stripe 开户表单；用户之后仍可在表单里改。 */
    public func prefillPaymentAccountBusinessDetails(paymentAccountId: String, source: PaymentAccountBusinessSource) async throws {
        let geocoded: GeoAddress? = if let point = source.location {
            try? await location.reverseGeocode(lat: point.latitude, lng: point.longitude).resultItems?.first?.address
        } else {
            nil
        }
        let city = geocoded?.locality?.trimmingCharacters(in: .whitespaces)
        try await api.prefillPaymentAccountBusinessDetails(paymentAccountId: paymentAccountId, PrefillPaymentAccountBusinessDetailsRequest(
            registeredName: source.name,
            displayName: source.name,
            phone: source.phone,
            address: geocoded?.businessAddress,
            productDescription: source.describe?(city?.isEmpty == false ? city : nil),
            businessUrl: source.website,
            mcc: source.mcc
        ))
    }

    /* ------------------------------ 付款卡 ------------------------------ */

    /** 平台 publishable key（绑卡的 SetupIntent 在平台账户上确认）。 */
    public func stripePublishableKey() async throws -> String {
        try await publicAPI.getPaymentsEnv().dataOrThrow("GetPaymentsEnv").env.stripePublishableKey
    }

    public func createSetupIntent() async throws -> SetupIntentResponse {
        try await api.createSetupIntent().dataOrThrow("CreateSetupIntent")
    }

    public func detachPaymentMethod(_ paymentMethodId: String) async throws {
        try await api.detachPaymentMethod(paymentMethodId: paymentMethodId)
        invalidate()
    }

    public func updatePaymentMethodNickname(_ paymentMethodId: String, nickname: String) async throws -> PaymentMethodItem {
        let item = try await api.updatePaymentMethod(paymentMethodId: paymentMethodId, UpdatePaymentMethodRequest(nickname: nickname))
            .dataOrThrow("UpdatePaymentMethod")
        invalidate()
        return item
    }

    public func setDefaultPaymentMethod(_ paymentMethodId: String) async throws -> PaymentMethodItem {
        let item = try await api.setDefaultPaymentMethod(paymentMethodId: paymentMethodId).dataOrThrow("SetDefaultPaymentMethod")
        invalidate()
        return item
    }

    public func invalidate() {
        bus.emit(.invalidatePayments)
    }

    public func onLogout() async throws {
        await paymentAccounts.clear()
        await paymentMethods.clear()
    }
}

/** 预填 Stripe 开户表单的商家资料（Android `PaymentAccountBusinessSource`）。 */
public struct PaymentAccountBusinessSource: Sendable {
    public let name: String
    public let phone: String?
    public let location: (latitude: Double, longitude: Double)?
    public let website: String?
    public let mcc: String?
    /** 经营说明模板；参数是从 [location] 反查出的城市（不知道时 nil）。 */
    public let describe: (@Sendable (String?) -> String)?

    public init(name: String, phone: String? = nil, location: (latitude: Double, longitude: Double)? = nil, website: String? = nil, mcc: String? = nil, describe: (@Sendable (String?) -> String)? = nil) {
        self.name = name
        self.phone = phone
        self.location = location
        self.website = website
        self.mcc = mcc
        self.describe = describe
    }
}

extension GeoAddress {
    /** Stripe 要的商家地址；缺街道、城市、邮编或国家任何一项都不给（Android `toBusinessAddress`）。 */
    var businessAddress: PaymentAccountBusinessAddress? {
        let line1 = [addressNumber, street].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let city = locality?.trimmingCharacters(in: .whitespaces) ?? ""
        let postalCode = postalCode?.trimmingCharacters(in: .whitespaces) ?? ""
        let country = country?.code2?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        guard !line1.isEmpty, !city.isEmpty, !postalCode.isEmpty, !country.isEmpty else { return nil }
        return PaymentAccountBusinessAddress(line1: line1, city: city, state: region?.code?.trimmingCharacters(in: .whitespaces) ?? "", postalCode: postalCode, country: country)
    }
}
