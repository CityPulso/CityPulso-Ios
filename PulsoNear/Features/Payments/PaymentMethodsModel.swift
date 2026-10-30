import Factory
import PulsoLinkCore
import PulsoLinkUI
@preconcurrency import StripePaymentSheet
import SwiftUI

/**
 * 当前账号保存的平台卡（对应 Android `PaymentMethodsViewModel`，WEB `Panel/Billing/PaymentMethods`）。
 * 付款方式页和 [HoldPaymentPanel] 共用。绑卡：拿 SetupIntent，用系统样式的 Stripe PaymentSheet 在平台账户上确认。
 */
@MainActor
@Observable
final class PaymentMethodsModel {
    private(set) var methods = Loadable<ListWithTotal<PaymentMethodItem>>()
    private(set) var adding = false
    private(set) var busyId: String?

    @ObservationIgnored @Injected(\.paymentsService) private var payments
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore

    var items: [PaymentMethodItem] { methods.data?.items ?? [] }
    var defaultId: String? { items.first(where: \.isDefault)?.id }

    func observe() async {
        for await response in payments.paymentMethods.stream(sessionStore.state.value.currentAccountId) {
            methods = methods.reduce(response)
        }
    }

    func refresh() {
        payments.invalidate()
    }

    /** 拿 SetupIntent，弹出 Stripe 的绑卡面板，完成后刷新列表。 */
    func startAdd() async {
        guard !adding else { return }
        adding = true
        defer { adding = false }
        do {
            let key = try await payments.stripePublishableKey()
            let intent = try await payments.createSetupIntent()
            STPAPIClient.shared.publishableKey = key
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
            let sheet = PaymentSheet(setupIntentClientSecret: intent.clientSecret, configuration: configuration)
            sheet.present(from: StripeAuthenticationContext().authenticationPresentingViewController()) { [weak self] result in
                self?.onAddResult(result)
            }
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payment_methods_add_failed")
        }
    }

    private func onAddResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed: refresh()
        case .canceled: break
        case let .failed(error): PulsoMessageCenter.shared.error(error, fallback: "payments_hold_failed")
        }
    }

    func setDefault(_ id: String) async {
        await mutate(id) { try await $0.setDefaultPaymentMethod(id) }
    }

    func rename(_ id: String, nickname: String) async {
        await mutate(id) { try await $0.updatePaymentMethodNickname(id, nickname: nickname.trimmingCharacters(in: .whitespaces)) }
    }

    func remove(_ id: String) async {
        await mutate(id) { try await $0.detachPaymentMethod(id) }
    }

    private func mutate(_ id: String, _ block: (PaymentsService) async throws -> some Sendable) async {
        busyId = id
        defer { busyId = nil }
        do {
            _ = try await block(payments)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payment_methods_action_failed")
        }
    }
}

extension PaymentMethodItem {
    var cardLabel: String { "\(brand.prefix(1).uppercased() + brand.dropFirst()) •••• \(last4)" }
    /** 有昵称用昵称，否则「品牌 •••• 尾号」（WEB `paymentMethodLabel`）。 */
    var title: String { nickname.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? cardLabel }
    var expiry: String { String(format: "%02d/%02d", expMonth, expYear % 100) }
}

/** 一张保存的卡；[selected] 非 nil 时可选（付款时选卡）。 */
struct PaymentMethodRow: View {
    let method: PaymentMethodItem
    var selected: Bool?

    var body: some View {
        HStack(spacing: 12) {
            if let selected {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            } else {
                Image(systemName: "creditcard").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: method.title).font(.body.weight(.medium))
                    if method.isDefault {
                        Text("payment_methods_default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: .capsule)
                            .foregroundStyle(.tint)
                    }
                }
                Text(verbatim: localizedFormat("payment_methods_expires", method.expiry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(.rect)
    }
}
