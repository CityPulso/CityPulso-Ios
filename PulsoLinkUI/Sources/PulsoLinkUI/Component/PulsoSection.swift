import SwiftUI

/*
 * 分组区块（Android `PulsoSection*`：设置、账号、编辑资料）：一行标题，下面一张细边框卡片装若干行。
 * 页面用 ScrollView + VStack 排这些区块（Android 也是 Column，不是 M3 List）。
 */

/** 区块标题：半粗、次要字色，左缩 4。 */
public struct PulsoSectionTitle: View {
    let title: LocalizedStringKey

    @Environment(\.pulsoPalette) private var palette

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, PulsoSpace.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/** 标题 + 卡片：卡片带 outlineVariant 细边（别处的卡片不描边，分组保留），行之间自动插分隔线。 */
public struct PulsoSection<Content: View>: View {
    let title: LocalizedStringKey?
    let content: Content

    @Environment(\.pulsoPalette) private var palette

    public init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PulsoSpace.s4) {
            if let title { PulsoSectionTitle(title) }
            PulsoCard(border: nil) {
                VStack(spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { PulsoSectionDivider() }
                            row
                        }
                    }
                }
            }
            .overlay { palette.cardShape.strokeBorder(palette.outlineVariant, lineWidth: pulsoHairline) }
            .clipShape(palette.cardShape)
        }
    }
}

/** 行间分隔线：左缩 48（让开图标），outlineVariant @ 60%。 */
public struct PulsoSectionDivider: View {
    @Environment(\.pulsoPalette) private var palette

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(palette.outlineVariant.opacity(0.6))
            .frame(height: pulsoHairline)
            .padding(.leading, PulsoSpace.s8)
    }
}

/**
 * 区块里的一行（Android `PulsoSectionRow`）：20pt 图标、标题（可带第二行 [supporting]）、右侧当前值 [value]、箭头。
 * 包在 `Button` / `NavigationLink` 里用（`.buttonStyle(.pulsoRow)`），按下整行变暗。
 * [tint] 给危险操作（退出登录、删除账号）用红色。
 */
public struct PulsoSectionRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let supporting: String?
    let value: String?
    let tint: Color?
    let showChevron: Bool
    let trailing: Trailing

    @Environment(\.pulsoPalette) private var palette

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        supporting: String? = nil,
        value: String? = nil,
        tint: Color? = nil,
        showChevron: Bool = true,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.supporting = supporting
        self.value = value
        self.tint = tint
        self.showChevron = showChevron
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: PulsoSpace.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(tint ?? palette.secondaryText)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: PulsoSpace.half) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(tint ?? palette.text)
                if let supporting {
                    Text(verbatim: supporting)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(verbatim: value)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            trailing
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(PulsoSpace.s4)
        .contentShape(Rectangle())
    }
}

/** 区块行的按下效果：整行铺一层正文色 8%（Android 方形 ripple）。 */
public struct PulsoRowButtonStyle: ButtonStyle {
    @Environment(\.pulsoPalette) private var palette

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? palette.text.opacity(0.08) : .clear)
    }
}

extension ButtonStyle where Self == PulsoRowButtonStyle {
    public static var pulsoRow: PulsoRowButtonStyle { PulsoRowButtonStyle() }
}

/**
 * 紧凑选择项（Android `PulsoChoiceChip`，筛选、日期条、预设值）：选中实心强调色、未选中 gray3 柔和底，都不描边。
 * [image] 是按原色画的运动插画（不随字色着色）。[alwaysPill] 不管圆角档位都是胶囊（地图图层预设）。
 */
public struct PulsoChoiceChip: View {
    let title: Text
    let image: Image?
    let selected: Bool
    let alwaysPill: Bool
    let action: () -> Void

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: Text, image: Image? = nil, selected: Bool, alwaysPill: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.selected = selected
        self.alwaysPill = alwaysPill
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: PulsoSpace.s1) {
                image?.resizable().scaledToFit().frame(width: 16, height: 16)
                title
                    .font(.subheadline.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? palette.onAccent : palette.gray.step(12))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: PulsoControlSize.small.height)
            .background(selected ? palette.accent.step(9) : palette.gray.step(3), in: alwaysPill ? AnyShape(Capsule()) : palette.controlShape)
        }
        .buttonStyle(PulsoPressScaleStyle())
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/** 按下微缩（Android `pulsoPressScale`）。 */
struct PulsoPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
