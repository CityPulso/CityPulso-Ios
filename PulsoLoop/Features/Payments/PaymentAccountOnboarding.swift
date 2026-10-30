import Foundation
import PulsoLinkCore
import PulsoLinkUI
@preconcurrency import StripeConnect
@preconcurrency import StripePayments
import UIKit

/** Stripe 的行业：7941 = 商业体育、运动场地（按时租场），和 WEB `VENUE_STRIPE_MCC` 一样。 */
let venueStripeMcc = "7941"

/**
 * Stripe 开户要的经营说明（只给 Stripe 风控看，所以是英文），覆盖球馆开放的所有运动；用户在表单里还能改。
 * 和 WEB `venueProductDescription` 同一个模板（Android `venueProductDescription`）。
 */
func venueProductDescription(name: String, sports: [VenueSport], city: String?) -> String {
    let names = sports.map { $0.rawValue.replacingOccurrences(of: "_", with: " ") }
    let courts = switch names.count {
    case 0: "sports courts"
    case 1: "\(names[0]) courts"
    default: "\(names.dropLast().joined(separator: ", ")) and \(names.last!) courts"
    }
    let place = city.map { " in \($0)" } ?? ""
    return "\(name) is a sports venue\(place) that rents \(courts) by the hour. "
        + "Customers book and pay for court time online through CityPulso or at the front desk, and can also buy venue memberships, "
        + "prepaid court-hour bundles, coaching sessions and courses. All purchases are for in-person use of the venue's facilities."
}

/**
 * Stripe Connect 嵌入式开户（Android `rememberPaymentAccountOnboardingLauncher`）：第一次拿到的 Account Session 同时给
 * publishable key 和第一个 client secret；SDK 之后刷新 secret 时再向后端要新的。关掉面板后回调 [onDismiss]（调用方去同步状态）。
 */
@MainActor
final class PaymentAccountOnboarding: NSObject, AccountOnboardingControllerDelegate {
    private var controller: AccountOnboardingController?
    private var onDismiss: (() -> Void)?

    func present(
        paymentAccountId: String,
        fetchSession: @escaping @Sendable (String) async throws -> PaymentAccountOnboardingSession,
        onDismiss: @escaping () -> Void
    ) async {
        let first: PaymentAccountOnboardingSession
        do {
            first = try await fetchSession(paymentAccountId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payment_accounts_onboarding_failed")
            return
        }
        let pending = PendingSecret(first.clientSecret)
        let manager = EmbeddedComponentManager(apiClient: STPAPIClient(publishableKey: first.publishableKey)) {
            if let secret = await pending.take() { return secret }
            do {
                return try await fetchSession(paymentAccountId).clientSecret
            } catch {
                await MainActor.run { PulsoMessageCenter.shared.error(error, fallback: "payment_accounts_onboarding_failed") }
                return nil
            }
        }
        let controller = manager.createAccountOnboardingController()
        controller.title = String(localized: "payment_accounts_onboarding_title")
        controller.delegate = self
        self.controller = controller
        self.onDismiss = onDismiss
        controller.present(from: StripeAuthenticationContext().authenticationPresentingViewController())
    }

    nonisolated func accountOnboardingDidExit(_: AccountOnboardingController) {
        Task { @MainActor in
            onDismiss?()
            controller = nil
            onDismiss = nil
        }
    }
}

/** 第一次用的 client secret，只用一次。 */
private actor PendingSecret {
    private var secret: String?

    init(_ secret: String) {
        self.secret = secret
    }

    func take() -> String? {
        defer { secret = nil }
        return secret
    }
}
