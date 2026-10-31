import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 邮箱管理（对应 Android `EmailAddressesScreen`）：平铺的邮箱行，每行下面是自己的按钮；设为主邮箱、删除先确认。 */
struct EmailAddressesView: View {
    @State private var model = EmailAddressesModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        content
            .navigationTitle("account_security_emails")
            .refreshable { await model.list.load() }
            .task { await model.list.observe() }
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
    }

    @ViewBuilder
    private var content: some View {
        if let emails = model.list.emails {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if emails.isEmpty {
                        PulsoEmptyState(Text("account_security_emails_none")).frame(minHeight: 200)
                    }
                    let verifiedCount = emails.filter { $0.verifiedAt != nil }.count
                    ForEach(emails) { email in
                        row(email, canDelete: !email.isPrimary && !(email.verifiedAt != nil && verifiedCount <= 1))
                        if email.id != emails.last?.id {
                            Divider().padding(.horizontal, PulsoSpace.s4)
                        }
                    }
                    Divider().padding(.vertical, PulsoSpace.s4)
                    // 添加邮箱：标题、描边输入框、一整行实心按钮（Android 同样不套卡片）。
                    VStack(alignment: .leading, spacing: PulsoSpace.s2) {
                        Text("account_security_add_email_address").font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                        PulsoTextField("account_security_add_email", text: $model.newEmail, prompt: "you@example.com")
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await model.addEmail() }
                        } label: {
                            PulsoButtonLabel("account_security_add_email_action", loading: model.isAdding)
                        }
                        .buttonStyle(.pulso(fullWidth: true))
                        .disabled(model.newEmail.trimmingCharacters(in: .whitespaces).isEmpty || model.isAdding)
                    }
                    .padding(.horizontal, PulsoSpace.s4)
                }
                .padding(.bottom, PulsoSpace.s6)
            }
        } else if let error = model.list.loadError {
            PulsoLoadErrorView(error) { Task { await model.list.load() } }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /** 一个邮箱：地址、主 / 已验证 / 未验证，下面是这一行的按钮；编辑和验证就地展开（Android `EmailRow`）。 */
    private func row(_ email: EmailItem, canDelete: Bool) -> some View {
        let busy = model.busyEmailId == email.id
        return VStack(alignment: .leading, spacing: PulsoSpace.s2) {
            Text(verbatim: email.email).font(.body.weight(.semibold)).foregroundStyle(palette.text)
            HStack(spacing: PulsoSpace.s2) {
                if email.isPrimary { badge("profile_badge_primary", color: palette.accent.step(11)) }
                if email.verifiedAt != nil {
                    badge("profile_badge_verified", color: RadixScale.green.lightStep(11))
                } else {
                    badge("profile_badge_unverified", color: palette.error)
                }
            }
            if model.editing?.id == email.id {
                PulsoTextField("login_email", text: $model.editValue)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack(spacing: PulsoSpace.s2) {
                    Button { Task { await model.saveEdit() } } label: { PulsoButtonLabel("profile_edit_save", loading: busy) }
                        .buttonStyle(.pulso())
                    Button("profile_dialog_cancel") { model.editing = nil }
                        .buttonStyle(.pulso(.outline))
                }
            } else if model.verifying?.id == email.id {
                PulsoTextField("signup_code", text: $model.verifyCode, prompt: "123456")
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .onChange(of: model.verifyCode) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { model.verifyCode = digits }
                    }
                HStack(spacing: PulsoSpace.s2) {
                    Button { Task { await model.sendCode() } } label: { PulsoButtonLabel("signup_send_code", loading: busy) }
                        .buttonStyle(.pulso(.outline))
                    Button { Task { await model.verify() } } label: { PulsoButtonLabel("account_security_verify", loading: busy) }
                        .buttonStyle(.pulso())
                        .disabled(model.verifyCode.count != 6)
                    Button("profile_dialog_cancel") { model.verifying = nil }
                        .buttonStyle(.pulso(.soft))
                }
            } else if !(email.isPrimary && email.verifiedAt != nil) || canDelete {
                HStack(spacing: PulsoSpace.s2) {
                    if !email.isPrimary {
                        Button("account_security_edit") { model.startEdit(email) }.buttonStyle(.pulso(.outline))
                    }
                    if email.verifiedAt == nil {
                        Button("account_security_verify") { model.startVerify(email) }.buttonStyle(.pulso())
                    } else if !email.isPrimary {
                        Button("account_security_set_primary") { model.confirmPrimary = email }.buttonStyle(.pulso(.soft))
                    }
                    if canDelete {
                        Button("profile_identities_delete") { model.confirmDelete = email }.buttonStyle(.pulso(.outline, tone: .gray))
                    }
                }
                .disabled(busy)
            }
        }
        .padding(PulsoSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ key: LocalizedStringKey, color: Color) -> some View {
        Text(key).font(.caption2.weight(.medium)).foregroundStyle(color)
    }

    private func isPresented<T>(_ keyPath: ReferenceWritableKeyPath<EmailAddressesModel, T?>) -> Binding<Bool> {
        Binding(get: { model[keyPath: keyPath] != nil }, set: { if !$0 { model[keyPath: keyPath] = nil } })
    }
}
