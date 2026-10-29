import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 当前账号的收款账户（Android `PaymentAccountsViewModel` 里选择器用到的那部分）。 */
@MainActor
@Observable
final class PaymentAccountsModel {
    private(set) var accounts = Loadable<ListWithTotal<PaymentAccountItem>>()

    @ObservationIgnored @Injected(\.paymentsService) private var payments
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore

    /** 能收款的账户才可被活动 / 球馆选用。 */
    var chargeable: [PaymentAccountItem] { accounts.data?.items.filter(\.chargesEnabled) ?? [] }

    func observe() async {
        for await response in payments.paymentAccounts.stream(sessionStore.state.value.currentAccountId) {
            accounts = accounts.reduce(response)
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
                shell?.push(LoopRoute.comingSoon(title: "payment_accounts_title", systemImage: "building.columns"))
            } label: {
                Label("payments_account_select_manage", systemImage: "building.columns")
            }
            .buttonStyle(.bordered)
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
