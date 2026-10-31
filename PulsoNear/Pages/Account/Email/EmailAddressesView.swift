import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 邮箱管理（对应 Android `EmailAddressesScreen`）：每行的操作在菜单里，验证用系统表单 sheet。 */
struct EmailAddressesView: View {
    @State private var model = EmailAddressesModel()

    var body: some View {
        content
            .navigationTitle("account_security_emails")
            .refreshable { await model.list.load() }
            .task { await model.list.observe() }
            .alert("account_security_edit", isPresented: isPresented(\.editing)) {
                TextField("login_email", text: $model.editValue)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Button("profile_edit_save") { Task { await model.saveEdit() } }
                Button("profile_dialog_cancel", role: .cancel) {}
            }
            .alert("account_security_set_primary_title", isPresented: isPresented(\.confirmPrimary), presenting: model.confirmPrimary) { email in
                Button("account_security_set_primary") { Task { await model.setPrimary(email) } }
                Button("profile_dialog_cancel", role: .cancel) {}
            } message: { _ in
                Text("account_security_set_primary_body")
            }
            .alert("account_security_delete_email_title", isPresented: isPresented(\.confirmDelete), presenting: model.confirmDelete) { email in
                Button("profile_identities_delete", role: .destructive) { Task { await model.delete(email) } }
                Button("profile_dialog_cancel", role: .cancel) {}
            } message: { _ in
                Text("account_security_delete_email_body")
            }
            .sheet(isPresented: isPresented(\.verifying)) {
                VerifyEmailSheet(model: model)
                    .presentationDetents([.medium])
            }
    }

    @ViewBuilder
    private var content: some View {
        if let emails = model.list.emails {
            Form {
                Section {
                    if emails.isEmpty {
                        Text("account_security_emails_none").foregroundStyle(.secondary)
                    }
                    ForEach(emails) { email in
                        row(email)
                    }
                }

                Section("account_security_add_email_address") {
                    TextField("account_security_add_email", text: $model.newEmail, prompt: Text(verbatim: "you@example.com"))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await model.addEmail() }
                    } label: {
                        if model.isAdding {
                            ProgressView()
                        } else {
                            Label("account_security_add_email_action", systemImage: "plus")
                        }
                    }
                    .disabled(model.newEmail.trimmingCharacters(in: .whitespaces).isEmpty || model.isAdding)
                }
            }
        } else if let error = model.list.loadError {
            PulsoLoadErrorView(error) { Task { await model.list.load() } }
        } else {
            ProgressView()
        }
    }

    private func row(_ email: EmailItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: email.email)
                HStack(spacing: 6) {
                    if email.isPrimary { badge("profile_badge_primary", tint: .accentColor) }
                    if email.verifiedAt != nil {
                        badge("profile_badge_verified", tint: .green)
                    } else {
                        badge("profile_badge_unverified", tint: .orange)
                    }
                }
            }
            Spacer()
            if model.busyEmailId == email.id {
                ProgressView()
            } else {
                Menu {
                    if !email.isPrimary {
                        Button("account_security_edit", systemImage: "pencil") { model.startEdit(email) }
                    }
                    if email.verifiedAt == nil {
                        Button("account_security_verify", systemImage: "checkmark.seal") { model.startVerify(email) }
                    } else if !email.isPrimary {
                        Button("account_security_set_primary", systemImage: "star") { model.confirmPrimary = email }
                    }
                    if !email.isPrimary {
                        Button("profile_identities_delete", systemImage: "trash", role: .destructive) { model.confirmDelete = email }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .disabled(email.isPrimary && email.verifiedAt != nil)
            }
        }
    }

    private func badge(_ key: LocalizedStringKey, tint: Color) -> some View {
        Text(key)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .capsule)
    }

    private func isPresented<T>(_ keyPath: ReferenceWritableKeyPath<EmailAddressesModel, T?>) -> Binding<Bool> {
        Binding(get: { model[keyPath: keyPath] != nil }, set: { if !$0 { model[keyPath: keyPath] = nil } })
    }
}

/** 验证邮箱：发验证码 → 输入 6 位码 → 验证。 */
private struct VerifyEmailSheet: View {
    @Bindable var model: EmailAddressesModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: model.verifying?.email ?? "")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("signup_code", text: $model.verifyCode, prompt: Text(verbatim: "123456"))
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .onChange(of: model.verifyCode) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(6))
                                if digits != value { model.verifyCode = digits }
                            }
                        Button("signup_send_code") { Task { await model.sendCode() } }
                            .buttonStyle(.pulso(.soft))
                            .disabled(model.busyEmailId != nil)
                    }
                }
            }
            .navigationTitle("account_security_verify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.verifying = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("account_security_verify") { Task { await model.verify() } }
                        .disabled(model.verifyCode.count != 6 || model.busyEmailId != nil)
                }
            }
        }
    }
}
