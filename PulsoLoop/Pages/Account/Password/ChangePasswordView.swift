import PulsoLinkUI
import SwiftUI

/** 修改密码（对应 Android `ChangePasswordScreen`）。 */
struct ChangePasswordView: View {
    @State private var model = ChangePasswordModel()

    var body: some View {
        Form {
            Section {
                SecureField("account_security_new_password", text: $model.newPassword)
                    .textContentType(.newPassword)
                SecureField("account_security_confirm_password", text: $model.confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                Text("account_security_new_password_hint")
            }

            Section {
                HStack {
                    TextField("signup_code", text: $model.verificationCode, prompt: Text(verbatim: "123456"))
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .onChange(of: model.verificationCode) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(6))
                            if digits != value { model.verificationCode = digits }
                        }
                    Button {
                        Task { await model.sendCode() }
                    } label: {
                        if model.sendingCode { ProgressView() } else { Text("signup_send_code") }
                    }
                    .buttonStyle(.glass)
                    .disabled(model.sendingCode)
                }
            } footer: {
                if let primary = model.emails.verifiedPrimaryEmail {
                    Text(verbatim: localizedFormat("account_security_password_code_hint", primary))
                } else if model.emails.emails != nil {
                    Text("account_security_password_need_primary")
                }
            }

            Section {
                Button {
                    Task { await model.changePassword() }
                } label: {
                    Group {
                        if model.submitting { ProgressView() } else { Text("account_security_change_password") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(model.submitting)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("account_security_change_password")
        .task { await model.emails.observe() }
    }
}
