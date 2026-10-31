import AuthenticationServices
import PulsoLinkUI
import SwiftUI

/**
 * 注册页（对应 Android `SignupScreen`）：极光背景全屏表单，邮箱、验证码 + 发送（柔和，倒计时）、密码两次，
 * 注册（实心）、通过 Apple 注册、使用 Google 登录（柔和 + 官方「G」），底部「去登录」。
 * 验证码用 `.oneTimeCode`，键盘直接带出邮件里的码。
 */
struct SignupView: View {
    @State private var model = SignupModel()
    @Environment(AuthNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        PulsoAuthForm(scrollSignal: model.errorText ?? model.infoText) {
            PulsoAuthHeader(logo: Image("logo"), title: "signup_title", subtitle: "signup_subtitle")
                .padding(.top, PulsoSpace.s9)

            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                PulsoTextField("signup_email", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: PulsoSpace.s2) {
                    PulsoTextField("signup_code", text: $model.verificationCode)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .onChange(of: model.verificationCode) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(6))
                            if digits != value { model.verificationCode = digits }
                        }
                    Button {
                        Task { await model.sendCode() }
                    } label: {
                        if model.resendCountdown > 0 {
                            Text(verbatim: "\(model.resendCountdown)s").monospacedDigit()
                        } else {
                            PulsoButtonLabel("signup_send_code", systemImage: "paperplane", loading: model.sendingCode)
                        }
                    }
                    .buttonStyle(.pulso(.soft))
                    .disabled(!model.canSendCode)
                }

                PulsoTextField(
                    "signup_password",
                    text: $model.password,
                    errorText: model.passwordTooShort ? String(localized: "signup_password_too_short") : nil,
                    secure: true
                )
                .textContentType(.newPassword)
                PulsoTextField(
                    "signup_confirm_password",
                    text: $model.confirmPassword,
                    errorText: model.passwordsMismatch ? String(localized: "signup_passwords_mismatch") : nil,
                    secure: true
                )
                .textContentType(.newPassword)

                if let errorText = model.errorText {
                    Text(verbatim: errorText).font(.caption).foregroundStyle(palette.error)
                }
                if let infoText = model.infoText {
                    Text(verbatim: infoText).font(.caption).foregroundStyle(palette.accent.step(9))
                }

                Button {
                    Task {
                        if await model.submit() { navigator.openLogin() }
                    }
                } label: {
                    PulsoButtonLabel("signup_submit", systemImage: "person.badge.plus", loading: model.loading)
                }
                .buttonStyle(.pulso(fullWidth: true))
                .disabled(!model.canSubmit)

                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = AppleIdToken.scopes
                } onCompletion: { result in
                    Task { await model.signInWithApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: PulsoControlSize.comfortable.height)
                .clipShape(palette.controlShape)
                .disabled(model.loading)

                Button {
                    Task { await model.signInWithGoogle() }
                } label: {
                    Label { Text("google_sign_in") } icon: { PulsoGoogleLogo() }
                }
                .buttonStyle(.pulso(.soft, fullWidth: true))
                .disabled(model.loading)
            }
            .padding(.top, PulsoSpace.s6)

            Button("signup_go_login") { navigator.openLogin() }
                .buttonStyle(.pulso(.ghost))
                .frame(maxWidth: .infinity)

            Spacer(minLength: PulsoSpace.s6)
        }
    }
}
