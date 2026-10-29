import SwiftUI

/** 登录页：系统表单，提交按钮用 Liquid Glass。 */
struct LoginView: View {
    @State private var model = LoginModel()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text("login_title")
                        .font(.largeTitle.bold())
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
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
                Toggle("login_remember_me", isOn: $model.rememberMe)
            } footer: {
                if let errorText = model.errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }

            Section {
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
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
