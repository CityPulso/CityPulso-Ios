import PulsoLinkUI
import SwiftUI

/**
 * 欢迎页（认证栈首页，对应 Android `WelcomeScreen`）：整屏背景图随翻页淡入淡出；logo + 应用名 →
 * 多页介绍（4.5 秒自动翻页、可手滑；当前页的点拉长成强调色胶囊）→「加入社区！」（实心，注册）/「登录」（柔和）→
 * 服务条款与隐私政策。
 * 背景图：亮 / 暗各一张，中文系统用中文版（见 Scripts/android_assets.py）。
 */
struct WelcomeView: View {
    private struct Page {
        let image: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private static let pages = [
        Page(image: "onboarding_discover", title: "welcome_page1_title", body: "welcome_page1_body"),
        Page(image: "onboarding_waitlist", title: "welcome_page2_title", body: "welcome_page2_body"),
        Page(image: "onboarding_create", title: "welcome_page3_title", body: "welcome_page3_body"),
    ]
    private static let termsOfService = URL(string: "https://pulsonear.com/termsofservices")!
    private static let privacyPolicy = URL(string: "https://pulsonear.com/privacypolicy")!
    private static let autoAdvance = Duration.milliseconds(4500)
    private static let logoSize: CGFloat = 44

    @Environment(AuthNavigator.self) private var navigator
    @Environment(\.pulsoPalette) private var palette
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
                        .foregroundStyle(palette.text)
                }
                .padding(.top, PulsoSpace.s6)

                TabView(selection: $page) {
                    ForEach(Self.pages.indices, id: \.self) { index in
                        VStack(spacing: PulsoSpace.s2) {
                            Spacer()
                            Text(Self.pages[index].title)
                                .font(.title2.bold())
                                .foregroundStyle(palette.text)
                            Text(Self.pages[index].body)
                                .font(.body)
                                .foregroundStyle(palette.text.opacity(0.88))
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, PulsoSpace.s4)
                        .padding(.vertical, PulsoSpace.s5)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots

                VStack(spacing: PulsoSpace.s2) {
                    Button {
                        navigator.openSignup()
                    } label: {
                        Label("welcome_get_started", systemImage: "arrow.right")
                    }
                    .buttonStyle(.pulso(fullWidth: true))

                    Button {
                        navigator.openLogin()
                    } label: {
                        Label("welcome_login", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                    .buttonStyle(.pulso(.soft, fullWidth: true))
                }
                .padding(.top, PulsoSpace.s5)
                .environment(\.pulsoControlSize, .comfortable)

                Text(terms)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .tint(palette.accent.step(11))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, PulsoSpace.s4)
            }
            .padding(.horizontal, PulsoSpace.s5)
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
                    .init(color: palette.background.opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.15),
                    .init(color: .clear, location: 0.48),
                    .init(color: palette.background.opacity(0.85), location: 0.64),
                    .init(color: palette.background.opacity(0.97), location: 0.78),
                    .init(color: palette.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: page)
    }

    /** 页码点：当前页拉长成 24pt 的强调色胶囊，其余 8pt 灰点。 */
    private var pageDots: some View {
        HStack(spacing: PulsoSpace.s2) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? palette.accent.step(9) : palette.gray.step(6))
                    .frame(width: index == page ? 24 : 8, height: 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: page)
        .accessibilityHidden(true)
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
