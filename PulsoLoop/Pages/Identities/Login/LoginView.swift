import AuthenticationServices
import PulsoLinkUI
import SwiftUI

/**
 * 登录页（对应 Android `LoginScreen`）：极光背景全屏表单，logo + 标题，邮箱 / 密码，登录（实心）、
 * 通过 Apple 登录（iOS 必须有）、使用 Google 登录（柔和 + 官方「G」），底部「去注册」。
 */
struct LoginView: View {
    @State private var model = LoginModel()
    @Environment(AuthNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        PulsoAuthForm(scrollSignal: model.errorText) {
            PulsoAuthHeader(logo: Image("logo"), title: "login_title", subtitle: "login_subtitle")
                .padding(.top, PulsoSpace.s9)

            VStack(spacing: PulsoSpace.s4) {
                PulsoTextField("login_email", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                PulsoTextField("login_password", text: $model.password, errorText: model.errorText, secure: true)
                    .textContentType(.password)
                    .onSubmit { Task { await model.login() } }

                PulsoSubmitButton("login_submit", systemImage: "rectangle.portrait.and.arrow.forward", phase: model.submit.phase) {
                    Task { await model.login() }
                } onSuccessShown: {
                    Task { await model.submit.successShown() }
                }
                .disabled(!model.canSubmit && !model.submit.phase.busy)

                SignInWithAppleButton(.signIn) { request in
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

            Button("login_go_signup") { navigator.openSignup() }
                .buttonStyle(.pulso(.ghost))
                .frame(maxWidth: .infinity)

            Spacer(minLength: PulsoSpace.s6)
        }
    }
}
