import PulsoLinkUI
import SwiftUI

/**
 * 欢迎页（认证栈首页，对应 Android `WelcomeScreen`）：整屏背景图随翻页淡入淡出；logo + 应用名 →
 * 多页介绍（4.5 秒自动翻页、可手滑，系统页码点）→「加入社区！」（注册）/「登录」→ 服务条款与隐私政策。
 * 背景图：亮色 day / 暗色 sunset，中文系统用中文版（见 Scripts/android_assets.py）。
 */
struct WelcomeView: View {
    private struct Page {
        let image: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private static let pages = [
        Page(image: "onboarding_discover", title: "welcome_page1_title", body: "welcome_page1_body"),
        Page(image: "onboarding_community", title: "welcome_page2_title", body: "welcome_page2_body"),
        Page(image: "onboarding_create", title: "welcome_page3_title", body: "welcome_page3_body"),
    ]
    private static let termsOfService = URL(string: "https://pulsoloop.com/termsofservices")!
    private static let privacyPolicy = URL(string: "https://pulsoloop.com/privacypolicy")!
    private static let autoAdvance = Duration.milliseconds(4500)
    private static let logoSize: CGFloat = 44

    @Environment(AuthNavigator.self) private var navigator
    @State private var page = 0

    var body: some View {
        ZStack {
            backgrounds
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image("logo")
                        .resizable()
                        .frame(width: Self.logoSize, height: Self.logoSize)
                        .clipShape(.rect(cornerRadius: Self.logoSize / 5))
                        .accessibilityLabel(Text("welcome_logo_desc"))
                    Text("app_display_name")
                        .font(.title.weight(.heavy))
                }
                .padding(.top, 24)

                TabView(selection: $page) {
                    ForEach(Self.pages.indices, id: \.self) { index in
                        VStack(spacing: 8) {
                            Spacer()
                            Text(Self.pages[index].title)
                                .font(.title2.bold())
                            Text(Self.pages[index].body)
                                .font(.body)
                                .opacity(0.88)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 48)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                VStack(spacing: 10) {
                    Button {
                        navigator.openSignup()
                    } label: {
                        Label("welcome_get_started", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        navigator.openLogin()
                    } label: {
                        Label("welcome_login", systemImage: "rectangle.portrait.and.arrow.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)

                Text(terms)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
            }
            .padding(.horizontal, 20)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task(id: page) {
            try? await Task.sleep(for: Self.autoAdvance)
            guard !Task.isCancelled else { return }
            withAnimation { page = (page + 1) % Self.pages.count }
        }
    }

    /** 背景图逐页淡入淡出；渐变遮罩顶部轻压托住 logo，下半屏淡到页面底色托住文字和按钮。 */
    private var backgrounds: some View {
        ZStack {
            ForEach(Self.pages.indices, id: \.self) { index in
                Image(Self.pages[index].image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .opacity(index == page ? 1 : 0)
                    .accessibilityHidden(true)
            }
            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground).opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.15),
                    .init(color: .clear, location: 0.48),
                    .init(color: Color(.systemBackground).opacity(0.85), location: 0.64),
                    .init(color: Color(.systemBackground).opacity(0.97), location: 0.78),
                    .init(color: Color(.systemBackground), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: page)
    }

    /** 条款行：两段链接点开系统浏览器。 */
    private var terms: AttributedString {
        var tos = AttributedString(localized: "welcome_terms_tos")
        tos.link = Self.termsOfService
        var privacy = AttributedString(localized: "welcome_terms_privacy")
        privacy.link = Self.privacyPolicy
        tos.font = .footnote.weight(.semibold)
        privacy.font = .footnote.weight(.semibold)
        return AttributedString(localized: "welcome_terms_prefix") + tos
            + AttributedString(localized: "welcome_terms_and") + privacy
            + AttributedString(localized: "welcome_terms_suffix")
    }
}
