import Factory
import PulsoLinkCore
import PulsoLinkUI
@preconcurrency import StripePayments
@preconcurrency import StripePaymentSheet
import SwiftUI
import UIKit

/**
 * 占座倒计时 + 选卡付款（对应 Android `HoldPaymentPanel`，WEB `HoldPayment`）。[payee] 是收款方（门店名 / 主办方）。
 * [pay] 用选中的平台卡在收款方 connected account 上扣款；卡要 3DS 时用 STPPaymentHandler 在同一个 connected account
 * 上完成验证。付款成功后调 [onPaid]，由调用方刷新状态。
 */
struct HoldPaymentPanel: View {
    let session: PaymentHoldActivity
    let payee: String
    let pay: (String) async throws -> PaymentAttempt
    let onPaid: () -> Void

    @State private var methods = PaymentMethodsModel()
    @State private var selectedId: String?
    @State private var error: String?
    @State private var paying = false
    @State private var paid = false
    @Environment(\.locale) private var locale
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    private var chosenId: String? {
        selectedId.flatMap { id in methods.items.contains { $0.id == id } ? id : nil } ?? methods.defaultId ?? methods.items.first?.id
    }

    private var expiry: Date? { DateTimeFormatters.parseInstant(session.expiresAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let expiry {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(expiry.timeIntervalSince(context.date)))
                    Label {
                        left == 0
                            ? Text("payments_hold_expired")
                            : Text(verbatim: localizedFormat("payments_hold_time_left", formatCountdown(left)))
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.footnote)
                    .foregroundStyle(left == 0 ? Color.red : Color.secondary)
                }
            }
            Text("payments_hold_pay_with").font(.subheadline.weight(.semibold))
            if methods.methods.data == nil, methods.methods.isLoading {
                Label { Text("payments_hold_loading_cards") } icon: { ProgressView() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if methods.items.isEmpty {
                Text("payments_hold_no_cards").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(methods.items, id: \.id) { method in
                    Button { selectedId = method.id } label: {
                        PaymentMethodRow(method: method, selected: method.id == chosenId)
                            .padding(10)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(method.id == chosenId ? Color.accentColor : Color(.separator)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button {
                    Task { await methods.startAdd() }
                } label: {
                    Label("payments_hold_add_card", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(paying || paid || methods.adding)
                Button("payments_hold_manage_cards") {
                    shell?.push(NearRoute.paymentMethods)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            if let error {
                Text(verbatim: error).font(.footnote).foregroundStyle(.red)
            }
            Label { Text(verbatim: localizedFormat("payments_hold_direct", payee)) } icon: { Image(systemName: "info.circle") }
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if let chosenId { Task { await submit(chosenId) } }
            } label: {
                HStack {
                    if paying { ProgressView() }
                    Image(systemName: "creditcard")
                    paid ? Text("payments_hold_paid")
                        : Text(verbatim: localizedFormat("payments_hold_pay", formatMoney(session.amount, currency: session.currency, locale: locale)))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(paying || paid || chosenId == nil || (expiry.map { $0 <= .now } ?? false))
        }
        .task { await methods.observe() }
    }

    private func submit(_ paymentMethodId: String) async {
        paying = true
        error = nil
        do {
            let attempt = try await pay(paymentMethodId)
            if attempt.status == .failed {
                paying = false
                error = String(localized: "payments_hold_failed")
            } else if let clientSecret = attempt.clientSecret {
                await handleNextAction(clientSecret)
            } else {
                complete()
            }
        } catch {
            paying = false
            self.error = UiError(error).text(fallback: String(localized: "payments_hold_failed"))
        }
    }

    /** 3DS 验证：在收款方 connected account 上处理 PaymentIntent 的下一步。 */
    private func handleNextAction(_ clientSecret: String) async {
        let client = STPAPIClient(publishableKey: session.publishableKey)
        client.stripeAccount = session.stripeAccountId
        let handler = STPPaymentHandler.shared()
        handler.apiClient = client
        let status: STPPaymentHandlerActionStatus = await withCheckedContinuation { continuation in
            handler.handleNextAction(forPayment: clientSecret, with: StripeAuthenticationContext(), returnURL: nil as String?) { status, _, _ in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .succeeded: complete()
        case .canceled: paying = false
        case .failed:
            paying = false
            error = String(localized: "payments_hold_failed")
        @unknown default:
            paying = false
        }
    }

    private func complete() {
        paying = false
        paid = true
        error = nil
        onPaid()
    }
}

/** 3DS 页面从当前最上层的视图控制器弹出。 */
final class StripeAuthenticationContext: NSObject, STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController ?? UIViewController()
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
