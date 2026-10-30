import Foundation
import PulsoLinkUI
@preconcurrency import StripePaymentSheet

/** 收款方 connected account 上的一个 PaymentIntent（Android `ConnectedPaymentIntent`）。 */
struct ConnectedPaymentIntent: Hashable, Sendable {
    let publishableKey: String
    let providerAccountId: String
    let clientSecret: String
}

/** 一次性付款（会员开卡、时长包、课程、赛事）的结果。 */
enum ConnectedPaymentResult: Sendable {
    case completed
    case canceled
    /** 显示给用户的文字：Stripe 的错误已经是本地化的用户文案（卡被拒、验证失败），否则用通用文案。 */
    case failed(String)
}

/**
 * Stripe PaymentSheet 在收款方 connected account 上确认 PaymentIntent（Android `rememberConnectedPaymentSheet`），
 * 用系统样式；不改全局的 Stripe 客户端。
 */
@MainActor
enum ConnectedPaymentSheet {
    static func present(_ intent: ConnectedPaymentIntent) async -> ConnectedPaymentResult {
        let client = STPAPIClient(publishableKey: intent.publishableKey)
        client.stripeAccount = intent.providerAccountId
        var configuration = PaymentSheet.Configuration()
        configuration.apiClient = client
        configuration.merchantDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        let sheet = PaymentSheet(paymentIntentClientSecret: intent.clientSecret, configuration: configuration)
        return await withCheckedContinuation { continuation in
            sheet.present(from: StripeAuthenticationContext().authenticationPresentingViewController()) { result in
                switch result {
                case .completed: continuation.resume(returning: .completed)
                case .canceled: continuation.resume(returning: .canceled)
                case let .failed(error):
                    let message = error.localizedDescription.trimmingCharacters(in: .whitespaces)
                    continuation.resume(returning: .failed(message.isEmpty ? String(localized: "payments_hold_failed") : message))
                }
            }
        }
    }
}
