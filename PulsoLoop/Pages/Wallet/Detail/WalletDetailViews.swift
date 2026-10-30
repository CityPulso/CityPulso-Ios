import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* 钱包里点进去的三页：我的会员卡、会员申请、时长包（Android `pages/membership/detail`、`pages/bundle/detail`）。 */

/** 一份会员详情的通用读取（Android `MyMembershipViewModel` / `MyMembershipPurchaseViewModel` / `MyBundleViewModel`）。 */
@MainActor
@Observable
final class WalletDetailModel<Value: Sendable> {
    private(set) var value = Loadable<Value>()
    private(set) var busy = false

    @ObservationIgnored private let stream: () -> AsyncStream<QueryResponse<Value>>
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(_ stream: @escaping () -> AsyncStream<QueryResponse<Value>>) {
        self.stream = stream
    }

    func observe() async {
        for await response in stream() {
            value = value.reduce(response)
        }
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    /** 跑一次写操作；成功返回 true，失败提示 [fallback]。 */
    func run(fallback: String.LocalizationValue, _ action: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await action()
            return true
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: fallback)
            return false
        }
    }
}

/** 我的一张会员卡（Android `MyMembershipScreen`）：卡面、有效期、续费或升级、查看球馆，下面是开卡 / 续费 / 升级记录。 */
struct MyMembershipView: View {
    @State private var model: WalletDetailModel<MyMembershipDetail>
    @Environment(\.locale) private var locale
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(membershipId: String) {
        let service = Container.shared.membershipService()
        _model = State(initialValue: WalletDetailModel { service.streamMyMembership(membershipId) })
    }

    var body: some View {
        Group {
            if let membership = model.value.data {
                List {
                    Section {
                        MembershipLevelCard(
                            name: membership.venueName,
                            icon: membership.levelIcon,
                            color: membership.levelColor,
                            discountPercent: membership.discountPercent,
                            tag: String(localized: membership.status.labelResource),
                            subtitle: membership.venueAddress,
                            footer: "\(membership.levelName) · \(formatMoney(membership.termPriceAmount, currency: membership.venueCurrency, locale: locale))",
                            portraitURL: model.imageURL(membership.venueCoverImageId),
                            portraitFallback: String(membership.venueName.prefix(1))
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        Text(verbatim: localizedFormat(
                            "my_membership_period",
                            VenueTime.date(membership.startsAt, timezone: membership.venueTimezone, locale: locale),
                            membership.endsAt.map { VenueTime.date($0, timezone: membership.venueTimezone, locale: locale) } ?? String(localized: "membership_lifetime")
                        ))
                        .font(.subheadline.monospacedDigit())
                        NavigationLink("my_membership_renew", value: LoopRoute.venue(venueId: membership.venueId, sheet: .membership))
                        NavigationLink("my_membership_open_venue", value: LoopRoute.venue(venueId: membership.venueId))
                    }
                    Section("my_membership_sections_ledger") {
                        if membership.ledger.isEmpty {
                            Text("my_membership_ledger_empty").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(membership.ledger, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(item.kind.labelKey).font(.subheadline.weight(.semibold))
                                    VenueChip(text: String(localized: item.status.labelResource), tone: item.status.tone)
                                    Spacer()
                                    Text(verbatim: formatMoney(item.chargedAmount, currency: item.currency, locale: locale)).font(.subheadline.monospacedDigit())
                                }
                                Text(verbatim: [
                                    item.fromLevelName.map { localizedFormat("my_membership_ledger_change", $0, item.toLevelName) } ?? item.toLevelName,
                                    membershipTermLabel(item.toDurationMonths),
                                    item.creditAmount > 0 ? localizedFormat("my_membership_ledger_credit", formatMoney(item.creditAmount, currency: item.currency, locale: locale)) : nil,
                                    String(localized: item.channel.labelResource),
                                ].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Text(verbatim: VenueTime.date(item.paidAt ?? item.createdAt, timezone: membership.venueTimezone, locale: locale))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else if let error = model.value.error, error.kind != .notFound {
                PulsoLoadErrorView(error) { Container.shared.membershipService().invalidate() }
            } else if model.value.error != nil {
                ContentUnavailableView {
                    Label("my_membership_not_found", systemImage: "person.text.rectangle")
                } description: {
                    Text("my_membership_not_found_body")
                } actions: {
                    Button("my_membership_back") { shell?.push(LoopRoute.wallet(tab: .memberships)) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("my_membership_title")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { Container.shared.membershipService().invalidate() }
        .task { await model.observe() }
    }
}

/** 一笔会员申请（Android `MyMembershipPurchaseScreen`）：灰色卡面、类型 · 等级 · 金额 · 方式、有效期，待确认时可以取消。 */
struct MyMembershipPurchaseView: View {
    let purchaseId: String
    @State private var model: WalletDetailModel<MyMembershipPurchase>
    @State private var askCancel = false
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(purchaseId: String) {
        self.purchaseId = purchaseId
        let service = Container.shared.membershipService()
        _model = State(initialValue: WalletDetailModel { service.streamMyPurchase(purchaseId) })
    }

    var body: some View {
        Group {
            if let purchase = model.value.data {
                let pending = purchase.status == .pending
                List {
                    Section {
                        MembershipLevelCard(
                            name: purchase.venueName,
                            icon: purchase.levelIcon,
                            color: purchase.levelColor,
                            discountPercent: purchase.discountPercent,
                            tag: String(localized: pending ? "my_memberships_purchase_unapproved" : "my_memberships_pending_badge"),
                            subtitle: purchase.venueAddress,
                            portraitURL: model.imageURL(purchase.venueCoverImageId),
                            portraitFallback: String(purchase.venueName.prefix(1)),
                            muted: true
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        VenueChip(
                            text: String(localized: pending ? "my_memberships_purchase_unapproved" : "my_memberships_pending_badge"),
                            tone: pending ? RadixScale.slate.lightStep(9) : RadixScale.amber.lightStep(9)
                        )
                        Text(verbatim: localizedFormat(
                            "my_memberships_purchase_summary",
                            String(localized: purchase.kind.pendingLabelResource),
                            purchase.levelName,
                            formatMoney(purchase.chargedAmount, currency: purchase.currency, locale: locale),
                            String(localized: purchase.paymentMethod.purchaseMethodResource)
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        if !purchase.startsAt.isEmpty {
                            Text(verbatim: localizedFormat(
                                "my_memberships_purchase_period",
                                VenueTime.date(purchase.startsAt, timezone: TimeZone.current.identifier, locale: locale),
                                purchase.endsAt.map { VenueTime.date($0, timezone: TimeZone.current.identifier, locale: locale) } ?? String(localized: "membership_lifetime")
                            ))
                            .font(.subheadline.monospacedDigit())
                        }
                        NavigationLink("my_memberships_open_venue", value: LoopRoute.venue(venueId: purchase.venueId))
                        if pending {
                            Button("my_memberships_purchase_cancel", role: .destructive) { askCancel = true }
                                .disabled(model.busy)
                        }
                    }
                }
            } else if let error = model.value.error {
                PulsoLoadErrorView(error) { Container.shared.membershipService().invalidate() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("my_memberships_purchase_title")
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text("my_memberships_purchase_cancel_title"), isPresented: $askCancel) {
            Button("my_memberships_purchase_cancel_confirm", role: .destructive) {
                Task {
                    let service = Container.shared.membershipService()
                    let id = purchaseId
                    if await model.run(fallback: "my_memberships_purchase_cancel_failed", { _ = try await service.cancelMyPurchase(id) }) { dismiss() }
                }
            }
            Button("my_memberships_purchase_keep", role: .cancel) {}
        } message: {
            Text("my_memberships_purchase_cancel_body")
        }
        .task { await model.observe() }
    }
}

/** 我的一个时长包（Android `MyBundleScreen`）：票面、实付和付款方式、购买日、有效期，去订场 / 再买；待确认时可以取消；时长明细。 */
struct MyBundleView: View {
    let bundleId: String
    @State private var model: WalletDetailModel<MyBundleDetail>
    @State private var askCancel = false
    @Environment(\.locale) private var locale
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(bundleId: String) {
        self.bundleId = bundleId
        let service = Container.shared.bundleService()
        _model = State(initialValue: WalletDetailModel { service.streamMyBundle(bundleId) })
    }

    var body: some View {
        Group {
            if let bundle = model.value.data {
                let state = bundle.state()
                List {
                    if state == .pending {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("my_bundle_pending_title").font(.subheadline.weight(.semibold))
                                Text(verbatim: pendingBody(bundle))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            .listRowBackground(RadixScale.amber.lightStep(9).opacity(0.12))
                        }
                    }
                    Section {
                        BundleTicket(item: bundle, coverURL: model.imageURL(bundle.venueCoverImageId))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        LabeledContent {
                            Text(verbatim: formatMoney(bundle.chargedAmount, currency: bundle.currency, locale: locale)
                                + (bundle.levelName.map { " · " + localizedFormat("my_bundle_member_price", $0) } ?? ""))
                                .monospacedDigit()
                        } label: {
                            Text("my_bundle_charged")
                        }
                        LabeledContent { Text(bundle.paymentMethod.labelKey) } label: { Text("my_bundle_method") }
                        LabeledContent {
                            Text(verbatim: VenueTime.date(bundle.paidAt ?? bundle.createdAt, timezone: bundle.venueTimezone, locale: locale))
                        } label: {
                            Text("my_bundle_bought")
                        }
                        LabeledContent {
                            Text(verbatim: bundle.expiresAt.map { VenueTime.date($0, timezone: bundle.venueTimezone, locale: locale) }
                                ?? bundle.validDays.map { localizedFormat("my_bundle_valid_days", $0) }
                                ?? String(localized: "bundle_no_expiry"))
                        } label: {
                            Text("my_bundle_validity")
                        }
                        if state == .active, let sport = bundle.sports.first {
                            NavigationLink("my_bundle_book", value: LoopRoute.venueBook(venueId: bundle.venueId, sport: sport))
                        }
                        NavigationLink("my_bundle_buy_more", value: LoopRoute.venue(venueId: bundle.venueId, sheet: .bundle))
                        if state == .pending {
                            Button("my_bundle_cancel_action", role: .destructive) { askCancel = true }
                                .disabled(model.busy)
                        }
                    }
                    Section("my_bundle_history") {
                        if bundle.ledger.isEmpty {
                            Text("bundle_ledger_empty").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(bundle.ledger, id: \.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.kind.labelKey).font(.subheadline.weight(.medium)).foregroundStyle(item.kind.tone)
                                    if let note = item.note, !note.isEmpty {
                                        Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(verbatim: DateTimeFormatters.monthDayTime(item.createdAt, locale: locale) ?? "").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(verbatim: (item.minutesDelta > 0 ? "+" : item.minutesDelta < 0 ? "−" : "") + formatBundleHours(abs(item.minutesDelta), locale: locale))
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
            } else if let error = model.value.error, error.kind != .notFound {
                PulsoLoadErrorView(error) { Container.shared.bundleService().invalidate() }
            } else if model.value.error != nil {
                ContentUnavailableView {
                    Label("my_bundle_not_found", systemImage: "ticket")
                } description: {
                    Text("my_bundle_not_found_body")
                } actions: {
                    Button("my_bundle_back") { shell?.push(LoopRoute.wallet(tab: .bundles)) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text(verbatim: model.value.data?.name ?? String(localized: "my_bundle_title")))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { Container.shared.bundleService().invalidate() }
        .alert(Text("my_bundle_cancel_title"), isPresented: $askCancel) {
            Button("my_bundle_cancel_action", role: .destructive) {
                Task {
                    let service = Container.shared.bundleService()
                    let id = bundleId
                    _ = await model.run(fallback: "my_bundle_cancel_failed") { _ = try await service.cancelMine(id) }
                }
            }
            Button("my_bundle_cancel_keep", role: .cancel) {}
        } message: {
            Text("my_bundle_cancel_body")
        }
        .task { await model.observe() }
    }

    private func pendingBody(_ bundle: MyBundleDetail) -> String {
        switch bundle.paymentMethod {
        case .phone: localizedFormat("my_bundle_pending_body_phone", bundle.venueName)
        case .offline: localizedFormat("my_bundle_pending_body_offline", bundle.venueName)
        case .platform: String(localized: "my_bundle_pending_body_platform")
        }
    }
}

extension MembershipLedgerStatus {
    var labelResource: String.LocalizationValue {
        switch self {
        case .pending: "membership_ledger_status_pending"
        case .paid: "membership_ledger_status_paid"
        case .canceled: "membership_ledger_status_canceled"
        }
    }

    var tone: Color {
        switch self {
        case .paid: RadixScale.green.lightStep(9)
        case .pending: RadixScale.amber.lightStep(9)
        case .canceled: RadixScale.slate.lightStep(9)
        }
    }
}

extension MembershipChannel {
    var labelResource: String.LocalizationValue {
        switch self {
        case .platform: "membership_channel_platform"
        case .offline: "membership_channel_offline"
        }
    }
}

extension MembershipPaymentMethod {
    /** 申请详情里的方式名。 */
    var purchaseMethodResource: String.LocalizationValue {
        switch self {
        case .phone: "my_memberships_purchase_method_phone"
        case .offline: "my_memberships_purchase_method_offline"
        case .platform: "my_memberships_purchase_method_platform"
        }
    }
}
