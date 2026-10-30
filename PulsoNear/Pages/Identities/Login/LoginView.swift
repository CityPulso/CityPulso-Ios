import AuthenticationServices
import GoogleSignInSwift
import PulsoLinkUI
import SwiftUI

/** 登录页（对应 Android `LoginScreen`）：系统表单，提交按钮用 Liquid Glass，Google 用官方按钮。 */
struct LoginView: View {
    @State private var model = LoginModel()
    @Environment(AuthNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                AuthHeader(title: "login_title", subtitle: "login_subtitle")
            }

            Section {
                TextField("login_email", text: $model.email, prompt: Text(verbatim: "you@example.com"))
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("login_password", text: $model.password)
                    .textContentType(.password)
                    .onSubmit { Task { await model.submit() } }
            } footer: {
                if let errorText = model.errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }

            Section {
                VStack(spacing: 12) {
                    Button {
                        Task { await model.submit() }
                    } label: {
                        Group {
                            if model.loading {
                                ProgressView()
                            } else {
                                Label("login_submit", systemImage: "rectangle.portrait.and.arrow.forward")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!model.canSubmit)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = AppleIdToken.scopes
                    } onCompletion: { result in
                        Task { await model.signInWithApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .disabled(model.loading)

                    GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide) {
                        Task { await model.signInWithGoogle() }
                    }
                    .disabled(model.loading)

                    Button("login_go_signup") { navigator.openSignup() }
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

/** 登录 / 注册页头：logo、标题、说明。 */
struct AuthHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("logo")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 64 / 5))
                .accessibilityHidden(true)
                .padding(.bottom, 8)
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
    }
}
