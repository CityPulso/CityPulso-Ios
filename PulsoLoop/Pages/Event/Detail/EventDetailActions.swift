import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 底栏（Android `<Sport>BottomBar`）：左边每人价格和开放 / 已满 / 已结束，右边当前唯一能做的操作。
 * 名额满了才出现候补。
 */
struct EventDetailBottomBar: View {
    let model: EventDetailModel
    let onEnd: () -> Void
    let onOpenChecklist: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        if let event = model.event {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            price(event).font(.headline.bold()).lineLimit(1)
                            EventTag(Text(model.openStatus.labelKey), accent: model.openStatus == .open)
                        }
                        if model.openStatus == .open {
                            Text(verbatim: seatsLeftLabel(model)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    action(event)
                }
                if model.joinBlockedByProfile {
                    Text("event_detail_pulser_required").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.horizontal, 12)
        }
    }

    private func price(_ event: any SportFullEvent) -> Text {
        if event.isFree { return Text("shell_calendar_badge_free") }
        guard let amount = event.priceAmount else { return Text(verbatim: "—") }
        return Text(verbatim: localizedFormat("event_detail_price_per_person", formatMoney(amount, currency: event.currency, locale: locale)))
    }

    @ViewBuilder
    private func action(_ event: any SportFullEvent) -> some View {
        let busy = model.isActionInProgress
        if model.isRosterLoading, !model.rosterReady {
            ProgressView()
        } else if model.isHost {
            HStack(spacing: 8) {
                if model.canOpenChecklist {
                    Button("event_detail_open_checklist", action: onOpenChecklist).buttonStyle(.bordered).disabled(busy)
                }
                if !event.isEnded {
                    Button("event_detail_end_session", action: onEnd).buttonStyle(.bordered).tint(.secondary).disabled(busy)
                }
            }
        } else if model.canRejoin {
            primary("event_detail_cancel_exit", busy: busy) { Task { await model.rejoin() } }.disabled(busy || !model.isPulser)
        } else if model.hasRegistration {
            Button("event_detail_view_registration") { model.sheet = .myRegistration }.buttonStyle(.bordered).disabled(busy)
        } else if model.canJoinDirectly {
            primary("event_detail_join", busy: busy) { model.sheet = .join }.disabled(busy || !model.isPulser)
        } else if model.canJoinWaitlist {
            primary("event_detail_join_waitlist", busy: busy) { model.sheet = .waitlist }.disabled(busy || !model.isPulser)
        } else {
            Button {} label: { Text(model.openStatus.labelKey) }.buttonStyle(.bordered).disabled(true)
        }
    }

    private func primary(_ title: LocalizedStringKey, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if busy { ProgressView() } else { Text(title) }
        }
        .buttonStyle(.glassProminent)
    }
}

/**
 * 我的报名卡（Android `<Sport>MyStatusCard`）：已报名 / 候补中 / 待退出 / 占座待付，涉及付款时带付款卡，
 * 下面「查看报名」和取消。
 */
struct MyStatusCard: View {
    let model: EventDetailModel
    let event: any SportFullEvent
    let registration: any SportRegistration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FactMarker(systemImage: copy.systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title).font(.subheadline.weight(.semibold))
                    Text(copy.body).font(.caption).foregroundStyle(.secondary)
                }
            }
            if registration.hasPaymentState {
                MyRegistrationPaymentCard(model: model, registration: registration, currency: event.currency)
            }
            HStack(spacing: 8) {
                Button { model.sheet = .myRegistration } label: { Text("event_detail_view_registration").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                if model.isHost {
                    HostCannotExitButton()
                } else if model.canRejoin {
                    Button { Task { await model.rejoin() } } label: {
                        Group { if model.isActionInProgress { ProgressView() } else { Text("event_detail_cancel_exit") } }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isActionInProgress)
                } else if model.canExit {
                    Button { model.sheet = .exit } label: { Text("event_detail_cancel_registration").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .disabled(model.isActionInProgress)
                }
            }
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var copy: (systemImage: String, title: LocalizedStringKey, body: LocalizedStringKey) {
        switch registration.status {
        case .waitlisted: ("hourglass", "event_detail_my_status_waitlisted_title", "event_detail_my_status_waitlisted_body")
        case .pendingExit: ("rectangle.portrait.and.arrow.right", "event_detail_my_status_pending_exit_title", "event_detail_my_status_pending_exit_body")
        case .awaitingPayment: ("hourglass", "event_detail_my_status_awaiting_title", "event_detail_my_status_awaiting_body")
        default: ("checkmark.circle", "event_detail_my_status_joined_title", "event_detail_my_status_joined_body")
        }
    }
}

extension SportRegistration {
    /** 有在线付款要显示：占座待付、有退款、或已付。 */
    var hasPaymentState: Bool { status == .awaitingPayment || refund != nil || paidAt != nil }
}

/** 发起人自己占着名额但不能退出；服务端会拒绝，所以按钮一开始就锁上。 */
struct HostCannotExitButton: View {
    var body: some View {
        Button {} label: {
            Label("event_detail_host_cannot_exit", systemImage: "lock").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(true)
    }
}

/** 我在这个活动的在线付款：占座待付（倒计时 + 立即付款）/ 付款确认中 / 退款进度 / 已付（Android `MyRegistrationPaymentCard`）。 */
struct MyRegistrationPaymentCard: View {
    let model: EventDetailModel
    let registration: any SportRegistration
    let currency: String

    @Environment(\.locale) private var locale

    var body: some View {
        if registration.status == .awaitingPayment, model.paidPending {
            Callout(tint: .blue, systemImage: "hourglass") { Text("event_detail_my_payment_confirming") }
        } else if registration.status == .awaitingPayment {
            Callout(tint: .blue, systemImage: "hourglass") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = secondsLeft(at: context.date)
                    VStack(alignment: .leading, spacing: 8) {
                        if let left {
                            Text(verbatim: localizedFormat("event_detail_my_payment_held_for", formatCountdown(left)))
                        } else {
                            Text("event_detail_my_payment_held")
                        }
                        Button { Task { await model.openPayment() } } label: {
                            if model.isPaymentLoading { ProgressView() } else { Label("event_detail_my_payment_pay_now", systemImage: "creditcard") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isPaymentLoading || left == 0)
                    }
                }
            }
        } else if let refund = registration.refund {
            let amount = registration.refundAmount.map { formatMoney($0, currency: currency, locale: locale) } ?? ""
            switch refund {
            case .pending:
                Callout(tint: .orange, systemImage: "arrow.uturn.backward") { Text(verbatim: localizedFormat("event_detail_my_payment_refund_pending", amount)) }
            case .succeeded:
                Callout(tint: .green, systemImage: "checkmark.circle") { Text(verbatim: localizedFormat("event_detail_my_payment_refund_succeeded", amount)) }
            case .failed:
                Callout(tint: .red, systemImage: "exclamationmark.triangle") { Text(verbatim: localizedFormat("event_detail_my_payment_refund_failed", amount)) }
            }
        } else if let paidAt = registration.paidAt {
            Callout(tint: .green, systemImage: "checkmark.circle") {
                Text(verbatim: localizedFormat("event_detail_my_payment_paid", DateTimeFormatters.monthDayTime(paidAt, locale: locale) ?? paidAt))
            }
        }
    }

    private func secondsLeft(at now: Date) -> Int? {
        guard let expiry = DateTimeFormatters.parseInstant(registration.paymentExpiresAt) else { return nil }
        return max(0, Int(expiry.timeIntervalSince(now)))
    }
}

/** 带色底的提示块（Android `Callout`）。 */
struct Callout<Content: View>: View {
    let tint: Color
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) { content }.font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}
