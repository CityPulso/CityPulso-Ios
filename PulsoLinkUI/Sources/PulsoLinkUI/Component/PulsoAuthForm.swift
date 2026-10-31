import SwiftUI

/**
 * 登录 / 注册的全屏表单壳（Android `AuthFormScaffold`）：极光背景 + 可滚动的一列，左右 24、底部 24，
 * 控件用 comfortable 高度（48）。[scrollSignal]（错误 / 提示）变化时滚到底，保证底部文案看得见。
 */
public struct PulsoAuthForm<Content: View>: View {
    let scrollSignal: String?
    let breathingCircles: Bool
    let content: Content

    public init(scrollSignal: String? = nil, breathingCircles: Bool = false, @ViewBuilder content: () -> Content) {
        self.scrollSignal = scrollSignal
        self.breathingCircles = breathingCircles
        self.content = content()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, PulsoSpace.s5)
                .padding(.bottom, PulsoSpace.s5)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollSignal) { _, signal in
                guard signal != nil else { return }
                withAnimation { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
        }
        .background { PulsoAuroraBackground(breathingCircles: breathingCircles) }
        .environment(\.pulsoControlSize, .comfortable)
    }

    private static var bottom: String { "pulso-auth-form-bottom" }
}

/** 登录 / 注册页头（Android LoginScreen 头部）：64pt logo、粗体大标题、次要说明。 */
public struct PulsoAuthHeader: View {
    let logo: Image
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    @Environment(\.pulsoPalette) private var palette

    public init(logo: Image, title: LocalizedStringKey, subtitle: LocalizedStringKey) {
        self.logo = logo
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(palette.text)
                .padding(.top, PulsoSpace.s5)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .padding(.top, PulsoSpace.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** 「使用 Google 登录」按钮的标志：Google 官方彩色「G」（同 Android play-services-base 的 googleg_standard_color_18）。 */
public struct PulsoGoogleLogo: View {
    public init() {}

    public var body: some View {
        Image("google_g", bundle: .pulsoLinkUI)
            .resizable()
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}
