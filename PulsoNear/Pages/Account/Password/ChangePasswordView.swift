import PulsoLinkUI
import SwiftUI

/** 修改密码（对应 Android `ChangePasswordScreen`）。 */
struct ChangePasswordView: View {
    @State private var model = ChangePasswordModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                PulsoTextField("account_security_new_password", text: $model.newPassword, hintText: String(localized: "account_security_new_password_hint"), secure: true)
                    .textContentType(.newPassword)
                PulsoTextField("account_security_confirm_password", text: $model.confirmPassword, secure: true)
                    .textContentType(.newPassword)
                Group {
                    if let primary = model.emails.verifiedPrimaryEmail {
                        Text(verbatim: localizedFormat("account_security_password_code_hint", primary))
                    } else if model.emails.emails != nil {
                        Text("account_security_password_need_primary")
                    }
                }
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                PulsoTextField("signup_code", text: $model.verificationCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .onChange(of: model.verificationCode) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { model.verificationCode = digits }
                    }
                // 发送验证码（描边）和修改密码（实心）各占一半（Android 底部一行）。
                HStack(spacing: PulsoSpace.s2) {
                    Button {
                        Task { await model.sendCode() }
                    } label: {
                        PulsoButtonLabel("signup_send_code", loading: model.sendingCode)
                    }
                    .buttonStyle(.pulso(.outline, fullWidth: true))
                    .disabled(model.sendingCode)
                    Button {
                        Task { await model.changePassword() }
                    } label: {
                        PulsoButtonLabel("account_security_change_password", loading: model.submitting)
                    }
                    .buttonStyle(.pulso(fullWidth: true))
                    .disabled(model.submitting)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("account_security_change_password")
        .task { await model.emails.observe() }
    }
}
