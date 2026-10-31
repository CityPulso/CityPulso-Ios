import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 收款账户（Android `PaymentAccountsScreen`）：说明、新建（名称、国家、联系邮箱，建好直接开户），每个账户一张卡：
 * 状态、能否收款 / 提现、完成开户或更新资料、刷新状态、用球馆资料预填。
 */
struct PaymentAccountsView: View {
    @State private var model = PaymentAccountsModel()
    @State private var creatingForm = false

    var body: some View {
        content
            .navigationTitle("payment_accounts_title")
            .refreshable { model.refresh() }
            .task { await model.observe() }
            .task { await model.observeDetails() }
    }

    @ViewBuilder
    private var content: some View {
        if model.accounts.data == nil, model.accounts.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.accounts.data == nil, let error = model.accounts.error {
            PulsoLoadErrorView(error) { model.refresh() }
        } else {
            List {
                Section {
                    Text("payment_accounts_intro").font(.subheadline).foregroundStyle(.secondary)
                    if creatingForm {
                        CreatePaymentAccountForm(model: model, onCancel: { creatingForm = false }) { label, country, email in
                            Task {
                                await model.create(label: label, country: country, email: email)
                                creatingForm = false
                            }
                        }
                    } else {
                        Button { creatingForm = true } label: { Label("payment_accounts_create", systemImage: "plus") }
                    }
                }
                if model.items.isEmpty, !creatingForm {
                    Section { Text("payment_accounts_empty").font(.subheadline).foregroundStyle(.secondary) }
                }
                ForEach(model.items, id: \.id) { account in
                    Section { AccountCard(account: account, model: model) }
                }
            }
        }
    }
}

private struct CreatePaymentAccountForm: View {
    let model: PaymentAccountsModel
    let onCancel: () -> Void
    let onSubmit: (String, PaymentAccountCountry, String) -> Void

    @State private var label = ""
    @State private var country = PaymentAccountCountry.ca
    @State private var email = ""
    @State private var touched = false

    var body: some View {
        let labelError = touched && label.trimmingCharacters(in: .whitespaces).isEmpty
        let emailError = touched && !email.contains("@")
        VStack(alignment: .leading, spacing: 10) {
            TextField("payment_accounts_label_placeholder", text: $label)
                .textFieldStyle(.roundedBorder)
            if labelError { Text("payment_accounts_label_required").font(.caption).foregroundStyle(.red) }
            HStack {
                TextField("payment_accounts_email_placeholder", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !model.accountEmails.isEmpty {
                    Menu {
                        ForEach(model.accountEmails, id: \.self) { item in
                            Button(item) { email = item }
                        }
                    } label: {
                        Label("payment_accounts_email_account", systemImage: "envelope")
                    }
                }
            }
            if emailError { Text("payment_accounts_email_required").font(.caption).foregroundStyle(.red) }
            Picker(selection: $country) {
                Text("payment_accounts_country_ca").tag(PaymentAccountCountry.ca)
                Text("payment_accounts_country_us").tag(PaymentAccountCountry.us)
            } label: {
                Text("payment_accounts_country")
            }
            .pickerStyle(.segmented)
            HStack {
                Button("event_detail_dialog_cancel", action: onCancel).buttonStyle(.pulso(.soft))
                Spacer()
                Button {
                    touched = true
                    guard !label.trimmingCharacters(in: .whitespaces).isEmpty, email.contains("@") else { return }
                    onSubmit(label, country, email)
                } label: {
                    if model.creating { ProgressView() } else { Text("payment_accounts_create_submit") }
                }
                .buttonStyle(.pulso())
                .disabled(model.creating)
            }
        }
        .onAppear { if email.isEmpty { email = model.primaryEmail } }
    }
}

private struct AccountCard: View {
    let account: PaymentAccountItem
    let model: PaymentAccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: account.label).font(.headline)
                Spacer()
                VenueChip(text: String(localized: account.status.labelResource), tone: account.status.tone)
            }
            Text(verbatim: "\(account.country) · \(account.defaultCurrency.uppercased())").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                VenueChip(text: String(localized: account.chargesEnabled ? "payment_accounts_charges_on" : "payment_accounts_charges_off"), tone: account.chargesEnabled ? RadixScale.green.lightStep(9) : RadixScale.slate.lightStep(9))
                VenueChip(text: String(localized: account.payoutsEnabled ? "payment_accounts_payouts_on" : "payment_accounts_payouts_off"), tone: account.payoutsEnabled ? RadixScale.green.lightStep(9) : RadixScale.slate.lightStep(9))
            }
            HStack {
                Button((account.detailsSubmitted ? "payment_accounts_update" : "payment_accounts_onboard") as LocalizedStringKey) {
                    Task { await model.onboard(account.id) }
                }
                .buttonStyle(.pulso())
                Button {
                    Task { await model.sync(account.id) }
                } label: {
                    if model.syncingId == account.id { ProgressView() } else { Text("payment_accounts_sync") }
                }
                .buttonStyle(.pulso(.soft))
                .disabled(model.syncingId == account.id)
            }
            if !model.prefillVenues.isEmpty, !account.detailsSubmitted {
                Menu {
                    ForEach(model.prefillVenues, id: \.id) { venue in
                        Button(venue.building.name) { Task { await model.prefill(account.id, from: venue) } }
                    }
                } label: {
                    if model.prefillingId == account.id { ProgressView() } else { Label("payment_accounts_prefill", systemImage: "storefront") }
                }
                Text("payment_accounts_prefill_hint").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
    }
}

extension PaymentsPaymentAccountStatus {
    var labelResource: String.LocalizationValue {
        switch self {
        case .onboarding: "payment_accounts_status_onboarding"
        case .active: "payment_accounts_status_active"
        case .restricted: "payment_accounts_status_restricted"
        case .disabled: "payment_accounts_status_disabled"
        }
    }

    var tone: Color {
        switch self {
        case .onboarding: RadixScale.amber.lightStep(9)
        case .active: RadixScale.green.lightStep(9)
        case .restricted: RadixScale.red.lightStep(9)
        case .disabled: RadixScale.slate.lightStep(9)
        }
    }
}
