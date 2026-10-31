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
    @Environment(\.pulsoPalette) private var palette

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
            ScrollView {
                VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                    Text("payment_accounts_intro").font(.subheadline).foregroundStyle(palette.secondaryText)
                    if creatingForm {
                        PulsoCard {
                            CreatePaymentAccountForm(model: model, onCancel: { creatingForm = false }) { label, country, email in
                                Task {
                                    await model.create(label: label, country: country, email: email)
                                    creatingForm = false
                                }
                            }
                            .padding(PulsoSpace.s5)
                        }
                    }
                    if model.items.isEmpty, !creatingForm {
                        PulsoEmptyState(Text("payment_accounts_empty")).frame(maxWidth: .infinity)
                    }
                    ForEach(model.items, id: \.id) { account in
                        PulsoCard { AccountCard(account: account, model: model).padding(PulsoSpace.s5) }
                    }
                }
                .padding(PulsoSpace.s4)
            }
            // Adding an account sits at the bottom of the page; the form opens at the top of the list.
            .safeAreaInset(edge: .bottom) {
                if !creatingForm {
                    Button { creatingForm = true } label: { PulsoButtonLabel("payment_accounts_create", systemImage: "plus") }
                        .buttonStyle(.pulso(fullWidth: true))
                        .padding(.horizontal, PulsoSpace.s4)
                        .padding(.vertical, PulsoSpace.s2)
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
        VStack(alignment: .leading, spacing: PulsoSpace.s3) {
            PulsoTextField(
                "payment_accounts_label", text: $label, prompt: String(localized: "payment_accounts_label_placeholder"),
                errorText: labelError ? String(localized: "payment_accounts_label_required") : nil
            )
            HStack(alignment: .top) {
                PulsoTextField(
                    "payment_accounts_email", text: $email, prompt: String(localized: "payment_accounts_email_placeholder"),
                    errorText: emailError ? String(localized: "payment_accounts_email_required") : nil
                )
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
            PulsoSectionTitle("payment_accounts_country")
            PulsoSegmentedControl([PaymentAccountCountry.ca, .us], selection: $country) {
                Text($0 == .ca ? "payment_accounts_country_ca" : "payment_accounts_country_us")
            }
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

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s3) {
            HStack {
                Text(verbatim: account.label).font(.headline).foregroundStyle(palette.text)
                Spacer()
                VenueChip(text: String(localized: account.status.labelResource), tone: account.status.tone)
            }
            Text(verbatim: "\(account.country) · \(account.defaultCurrency.uppercased()) · \(account.providerAccountId)").font(.subheadline).foregroundStyle(palette.secondaryText).lineLimit(1)
            HStack(spacing: 6) {
                VenueChip(text: String(localized: account.chargesEnabled ? "payment_accounts_charges_on" : "payment_accounts_charges_off"), tone: account.chargesEnabled ? RadixScale.green.lightStep(9) : palette.secondaryText)
                VenueChip(text: String(localized: account.payoutsEnabled ? "payment_accounts_payouts_on" : "payment_accounts_payouts_off"), tone: account.payoutsEnabled ? RadixScale.green.lightStep(9) : palette.secondaryText)
            }
            HStack {
                Button((account.detailsSubmitted ? "payment_accounts_update" : "payment_accounts_onboard") as LocalizedStringKey) {
                    Task { await model.onboard(account.id) }
                }
                .buttonStyle(.pulso(fullWidth: true))
                Button {
                    Task { await model.sync(account.id) }
                } label: {
                    if model.syncingId == account.id { ProgressView() } else { PulsoButtonLabel("payment_accounts_sync", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.pulso(.soft, tone: .gray))
                .fixedSize()
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
                Text("payment_accounts_prefill_hint").font(.caption).foregroundStyle(palette.secondaryText)
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
