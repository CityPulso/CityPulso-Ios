import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 当前账号的收款账户 + 新建 / 开户 / 同步 / 用门店资料预填（Android `PaymentAccountsViewModel`）；收款账户页和选择器共用。 */
@MainActor
@Observable
final class PaymentAccountsModel {
    private(set) var accounts = Loadable<ListWithTotal<PaymentAccountItem>>()
    private(set) var accountEmails: [String] = []
    private(set) var primaryEmail = ""
    private(set) var creating = false
    private(set) var syncingId: String?
    /** 可以用来预填 Stripe 开户表单的门店；没有门店时不显示预填按钮。 */
    private(set) var prefillVenues: [MyVenue] = []
    private(set) var prefillingId: String?

    @ObservationIgnored @Injected(\.paymentsService) private var payments
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.profileStore) private var profileStore
    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored private let onboarding = PaymentAccountOnboarding()
    /** 请求体不变时复用幂等键，重复提交不会建出第二个 Stripe 账户。 */
    @ObservationIgnored private var idempotency: (body: CreatePaymentAccountRequest, key: String)?

    var items: [PaymentAccountItem] { accounts.data?.items ?? [] }
    /** 能收款的账户才可被活动 / 门店选用。 */
    var chargeable: [PaymentAccountItem] { items.filter(\.chargesEnabled) }

    func observe() async {
        for await response in payments.paymentAccounts.stream(sessionStore.state.value.currentAccountId) {
            accounts = accounts.reduce(response)
        }
    }

    /** 收款账户页另外要的：账号邮箱、可以拿来预填的门店。 */
    func observeDetails() async {
        let venueService = venueService
        await concurrently([
            {
                for await info in self.profileStore.current.values() {
                    let emails = (info?.emails ?? []).map { $0.email.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    self.accountEmails = emails.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                    self.primaryEmail = info?.primaryEmail ?? ""
                }
            },
            {
                // 预填只是方便：拿不到门店就不显示按钮。
                if let venues = try? await venueService.myVenues() { self.prefillVenues = venues }
            },
        ])
    }

    func refresh() {
        payments.invalidate()
    }

    /** 新建成功后直接打开开户。 */
    func create(label: String, country: PaymentAccountCountry, email: String) async {
        let body = CreatePaymentAccountRequest(label: label.trimmingCharacters(in: .whitespaces), country: country.code, email: email.trimmingCharacters(in: .whitespaces))
        let key = idempotency.flatMap { $0.body == body ? $0.key : nil } ?? UUID().uuidString
        idempotency = (body, key)
        creating = true
        defer { creating = false }
        do {
            let account = try await payments.createPaymentAccount(body, idempotencyKey: key)
            idempotency = nil
            await onboard(account.id)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payment_accounts_create_failed")
        }
    }

    /** 打开（或重新打开）Stripe 开户；关掉后同步一次状态。 */
    func onboard(_ paymentAccountId: String) async {
        let payments = payments
        await onboarding.present(paymentAccountId: paymentAccountId, fetchSession: { id in
            try await payments.createPaymentAccountOnboardingSession(paymentAccountId: id)
        }) { [weak self] in
            Task { await self?.sync(paymentAccountId) }
        }
    }

    func sync(_ paymentAccountId: String) async {
        syncingId = paymentAccountId
        defer { syncingId = nil }
        do {
            _ = try await payments.syncPaymentAccount(paymentAccountId: paymentAccountId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payment_accounts_sync_failed")
        }
    }

    /** 用门店的名字、电话、地址预填 Stripe 开户表单，成功后打开开户。 */
    func prefill(_ paymentAccountId: String, from venue: MyVenue) async {
        let lat = venue.building.locationLat
        let lng = venue.building.locationLng
        let name = venue.building.name
        let activityTypes = venue.activityTypes
        let source = PaymentAccountBusinessSource(
            name: name,
            phone: venue.phone,
            location: lat.flatMap { lat in lng.map { (lat, $0) } },
            website: venue.website,
            mcc: venueStripeMcc,
            describe: { city in venueProductDescription(name: name, activityTypes: activityTypes, city: city) }
        )
        prefillingId = paymentAccountId
        defer { prefillingId = nil }
        do {
            try await payments.prefillPaymentAccountBusinessDetails(paymentAccountId: paymentAccountId, source: source)
            PulsoMessageCenter.shared.success("payment_accounts_prefill_done")
            await onboard(paymentAccountId)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "payment_accounts_prefill_failed")
        }
    }
}

/**
 * 选择接收在线付款的收款账户（Android `PaymentAccountPicker`，WEB `PaymentAccountSelect`）：只列出能收款的账户；
 * 已选账户失去收款能力时提示。[errorText] 由调用方的表单校验提供。
 */
struct PaymentAccountPicker: View {
    @Binding var selectedId: String?
    var errorText: LocalizedStringKey?

    @State private var model = PaymentAccountsModel()
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("payments_account_select_label").font(.subheadline.weight(.semibold))
            if model.accounts.data == nil, model.accounts.isLoading {
                Label { Text("payments_account_select_loading") } icon: { ProgressView() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.chargeable.isEmpty {
                Text("payments_account_select_none").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(model.chargeable, id: \.id) { account in
                    Button { selectedId = account.id } label: { option(account) }
                        .buttonStyle(.plain)
                }
            }
            if let selectedId, model.accounts.data != nil, !model.chargeable.contains(where: { $0.id == selectedId }) {
                Text("payments_account_select_not_ready").font(.footnote).foregroundStyle(.red)
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            Text("payments_account_select_note").font(.footnote).foregroundStyle(.secondary)
            Button {
                shell?.push(NearRoute.paymentAccounts)
            } label: {
                Label("payments_account_select_manage", systemImage: "building.columns")
            }
            .buttonStyle(.pulso(.soft))
        }
        .task { await model.observe() }
        .onChange(of: model.chargeable.map(\.id)) { _, ids in
            if selectedId == nil, ids.count == 1 { selectedId = ids[0] }
        }
    }

    private func option(_ account: PaymentAccountItem) -> some View {
        let selected = account.id == selectedId
        return HStack(spacing: 10) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.label).font(.body.weight(.medium))
                Text(verbatim: [account.country, account.defaultCurrency.uppercased()].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color(.separator)))
        .contentShape(.rect)
    }
}
