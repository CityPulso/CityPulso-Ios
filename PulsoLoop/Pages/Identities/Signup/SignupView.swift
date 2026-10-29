import GoogleSignInSwift
import SwiftUI

/** 注册页（对应 Android `SignupScreen`）：系统表单，验证码用 `.oneTimeCode` 让键盘直接带出邮件里的码。 */
struct SignupView: View {
    @State private var model = SignupModel()
    @Environment(AuthNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                AuthHeader(title: "signup_title", subtitle: "signup_subtitle")
            }

            Section {
                TextField("signup_email", text: $model.email, prompt: Text(verbatim: "you@example.com"))
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                        if model.sendingCode {
                            ProgressView()
                        } else if model.resendCountdown > 0 {
                            Text(verbatim: "\(model.resendCountdown)s").monospacedDigit()
                        } else {
                            Label("signup_send_code", systemImage: "paperplane")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(!model.canSendCode)
                }
            }

            Section {
                SecureField("signup_password", text: $model.password)
                    .textContentType(.newPassword)
                SecureField("signup_confirm_password", text: $model.confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if model.passwordTooShort {
                        Text("signup_password_too_short").foregroundStyle(.red)
                    }
                    if model.passwordsMismatch {
                        Text("signup_passwords_mismatch").foregroundStyle(.red)
                    }
                    if let errorText = model.errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                    if let infoText = model.infoText {
                        Text(infoText).foregroundStyle(.tint)
                    }
                }
            }

            Section {
                VStack(spacing: 12) {
                    Button {
                        Task {
                            if await model.submit() { navigator.openLogin() }
                        }
                    } label: {
                        Group {
                            if model.loading {
                                ProgressView()
                            } else {
                                Label("signup_submit", systemImage: "person.badge.plus")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!model.canSubmit)

                    GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide) {
                        Task { await model.signInWithGoogle() }
                    }
                    .disabled(model.loading)

                    Button("signup_go_login") { navigator.openLogin() }
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
