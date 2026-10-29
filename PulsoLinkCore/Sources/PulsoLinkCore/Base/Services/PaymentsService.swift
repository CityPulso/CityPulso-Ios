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

    public init(api: PaymentsAPI, publicAPI: PaymentsPublicAPI, bus: PaymentsEventBus) {
        self.api = api
        self.publicAPI = publicAPI
        self.bus = bus
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

    public func prefillPaymentAccountBusinessDetails(paymentAccountId: String, _ body: PrefillPaymentAccountBusinessDetailsRequest) async throws {
        try await api.prefillPaymentAccountBusinessDetails(paymentAccountId: paymentAccountId, body)
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
