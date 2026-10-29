import PulsoLinkUI
import SwiftUI

/** 登录页：全屏布局（手机端不套卡片）。 */
struct LoginView: View {
    private static let logoSize: CGFloat = 64

    @State private var model = LoginModel()
    @Environment(\.pulsoTheme) private var theme

    var body: some View {
        let dimensions = theme.dimensions
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: dimensions.space6 * 2)

                Image("AppLogo")
                    .resizable()
                    .frame(width: Self.logoSize, height: Self.logoSize)
                    .accessibilityHidden(true)
                Spacer().frame(height: dimensions.space5)
                Text("login_title")
                    .font(.title.bold())
                    .foregroundStyle(theme.colors.onSurface)

                Spacer().frame(height: dimensions.space6)

                VStack(alignment: .leading, spacing: dimensions.space4) {
                    PulsoTextField("login_email", text: $model.email, size: .comfortable)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    PulsoTextField(
                        "login_password",
                        text: $model.password,
                        errorText: model.errorText,
                        secure: true,
                        size: .comfortable
                    )
                    .textContentType(.password)
                    .onSubmit { Task { await model.submit() } }

                    PulsoCheckbox("login_remember_me", isOn: $model.rememberMe)

                    PulsoButton(
                        "login_submit",
                        systemImage: "rectangle.portrait.and.arrow.forward",
                        size: .comfortable,
                        loading: model.loading
                    ) {
                        Task { await model.submit() }
                    }
                    .disabled(!model.canSubmit)
                }
            }
            .padding(.horizontal, dimensions.space5)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.background.ignoresSafeArea())
    }
}
