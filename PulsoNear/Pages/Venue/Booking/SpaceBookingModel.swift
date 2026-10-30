import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 取消弹层：原因、退款预估（在线付款 / 时长包才有）、提交中、错误（弹层里显示）。 */
struct SpaceCancelDialogState {
    var reason = ""
    var preview: Loadable<SpaceRefundPreviewUi>?
    var submitting = false
    var error: String?
}

/**
 * 我的一条订场（Android `<ActivityType>SpaceBookingViewModel`，三种活动类型共用）：待付款时拉付款会话；hold 没结束或退款处理中时
 * 每 5 秒重拉；取消前看能退多少。
 */
@MainActor
@Observable
final class SpaceBookingModel {
    static let settlingPoll = Duration.seconds(5)
    static let reasonMax = 500

    let activityType: VenueActivityType
    let bookingId: String

    private(set) var booking = Loadable<MySpaceBookingUi>()
    private(set) var payment: Loadable<PaymentHoldActivity>?
    /** 付款面板已完成、等 webhook 落库的本地标记。 */
    private(set) var paid = false
    var cancel: SpaceCancelDialogState?

    @ObservationIgnored private let service: any VenueBookingService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(activityType: VenueActivityType, bookingId: String) {
        self.activityType = activityType
        self.bookingId = bookingId
        service = Container.shared.venueBookingServices()[activityType]!
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    var needsPayment: Bool {
        guard let booking = booking.data else { return false }
        return booking.status == .awaitingPayment && booking.paymentMethod == .platform && !paid
    }

    func canCancel(now: Date) -> Bool {
        guard let booking = booking.data else { return false }
        return spaceBookingActiveStatuses.contains(booking.status) && (DateTimeFormatters.parseInstant(booking.startsAt) ?? .distantPast) > now
    }

    /** 已在线付款的确认预订：取消按政策快照退款。 */
    var paidOnline: Bool { booking.data.map { $0.paymentMethod == .platform && $0.status == .confirmed } ?? false }

    /** hold 没结束 / 退款处理中（WEB `isSpaceBookingSettling`）。 */
    private var isSettling: Bool {
        guard let booking = booking.data else { return false }
        return booking.status == .pending || booking.status == .awaitingPayment || booking.refundStatus == "pending"
    }

    func observe() async {
        await concurrently([
            {
                for await response in self.service.myBooking(self.bookingId) {
                    self.booking = self.booking.reduce(response)
                    if self.needsPayment, self.payment == nil { await self.loadPayment() }
                }
            },
            {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.settlingPoll)
                    // 后台轮询：某次失败就等下一次。
                    if self.isSettling { _ = try? await self.service.refetchMyBooking(self.bookingId) }
                }
            },
        ])
    }

    private func loadPayment() async {
        payment = Loadable()
        do {
            payment = Loadable(data: try await service.bookingPayment(bookingId), isLoading: false)
        } catch {
            payment = Loadable(isLoading: false, error: UiError(error))
        }
    }

    /** 重试：成功时订阅会再发一次，失败时报错。 */
    func refresh() {
        let service = service
        let bookingId = bookingId
        Task { _ = try? await service.refetchMyBooking(bookingId) }
    }

    func pay(_ paymentMethodId: String) async throws -> PaymentAttempt {
        try await service.payBooking(bookingId, paymentMethodId: paymentMethodId)
    }

    func onPaid() {
        paid = true
        refresh()
    }

    func openCancel() {
        let needsPreview = paidOnline
        cancel = SpaceCancelDialogState(preview: needsPreview ? Loadable() : nil)
        guard needsPreview else { return }
        let service = service
        let bookingId = bookingId
        Task {
            do {
                let preview = try await service.refundPreview(bookingId)
                cancel?.preview = Loadable(data: preview, isLoading: false)
            } catch {
                cancel?.preview = Loadable(isLoading: false)
                cancel?.error = UiError(error).text(fallback: String(localized: "space_booking_refund_preview_failed"))
            }
        }
    }

    func setCancelReason(_ value: String) {
        cancel?.reason = String(value.prefix(Self.reasonMax))
    }

    func confirmCancel() async {
        guard let dialog = cancel else { return }
        cancel?.submitting = true
        cancel?.error = nil
        let reason = dialog.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await service.cancelBooking(bookingId, reason: reason.isEmpty ? nil : reason)
            cancel = nil
        } catch {
            cancel?.submitting = false
            cancel?.error = UiError(error).text(fallback: String(localized: "space_booking_cancel_failed"))
        }
    }
}
