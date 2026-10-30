import Foundation
import PulsoLinkCore
import PulsoLinkUI
@preconcurrency import StripeConnect
@preconcurrency import StripePayments
import UIKit

/** Stripe 的行业：7999 = 休闲娱乐服务，和 WEB `VENUE_STRIPE_MCC` 一样（Android Near `VENUE_STRIPE_MCC`）。 */
let venueStripeMcc = "7999"

/**
 * Stripe 开户要的经营说明（只给 Stripe 风控看，所以是英文），覆盖门店开放的所有业态；用户在表单里还能改。
 * 和 WEB `venueProductDescription` 同一个模板（Android Near `venueProductDescription`）。
 */
func venueProductDescription(name: String, activityTypes: [VenueActivityType], city: String?) -> String {
    let names = activityTypes.map { $0.rawValue.replacingOccurrences(of: "_", with: " ") }
    let offers = switch names.count {
    case 0: "leisure"
    case 1: names[0]
    default: "\(names.dropLast().joined(separator: ", ")) and \(names.last!)"
    }
    let place = city.map { " in \($0)" } ?? ""
    return "\(name) is a \(offers) venue\(place) that rents rooms, tables and game sessions by the hour or by the session. "
        + "Customers book and pay online through CityPulso or at the front desk, and can also buy venue memberships. "
        + "All purchases are for in-person use of the venue's facilities."
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
