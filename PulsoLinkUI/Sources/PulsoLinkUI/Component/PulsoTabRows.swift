import SwiftUI

/**
 * 一级标签（Android `PulsoUnderlineTabRow`，运动类型等）：选中项的字和下面 20×3 的短横线都是强调色、加粗；
 * 横线在切换时从当前项滑到目标项，选中项滚到行中间。横向可滚动。
 * [image] 是按原色画的图标（运动插画）；[systemImage] 是跟字同色的线条图标；[badge] 是字右边的红色数字。
 */
public struct PulsoUnderlineTabRow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Text
    let image: ((Option) -> Image?)?
    let systemImage: ((Option) -> String?)?
    let badge: ((Option) -> Int?)?

    @Environment(\.pulsoPalette) private var palette
    @Namespace private var indicator

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        image: ((Option) -> Image?)? = nil,
        systemImage: ((Option) -> String?)? = nil,
        badge: ((Option) -> Int?)? = nil,
        label: @escaping (Option) -> Text
    ) {
        self.options = options
        _selection = selection
        self.label = label
        self.image = image
        self.systemImage = systemImage
        self.badge = badge
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: PulsoSpace.s4) {
                    ForEach(options, id: \.self) { option in
                        tab(option)
                            .id(option)
                    }
                }
                .padding(.horizontal, PulsoSpace.s2)
                .padding(.top, PulsoSpace.s1)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection, initial: true) { _, selected in
                withAnimation(.easeOut(duration: 0.28)) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .background(palette.background)
    }

    private func tab(_ option: Option) -> some View {
        let active = option == selection
        let color = active ? palette.accent.step(9) : palette.secondaryText
        return Button {
            withAnimation(.easeOut(duration: 0.28)) { selection = option }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: PulsoSpace.s1) {
                    if let name = systemImage?(option) {
                        Image(systemName: name).font(.footnote).foregroundStyle(color)
                    }
                    if let image = image?(option) {
                        image.resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                    label(option)
                        .font(.subheadline.weight(active ? .bold : .medium))
                        .foregroundStyle(color)
                        .lineLimit(1)
                    if let count = badge?(option), count > 0 {
                        Text(verbatim: count > 99 ? "99+" : "\(count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, PulsoSpace.s1)
                            .background(palette.error, in: palette.chipShape)
                    }
                }
                .padding(.horizontal, PulsoSpace.s2)
                .padding(.vertical, PulsoSpace.s1)
                ZStack {
                    if active {
                        Capsule()
                            .fill(palette.accent.step(9))
                            .frame(width: 20, height: 3)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
                .frame(height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/**
 * 二级文字标签（Android `PulsoHighlightTabRow`）：选中强调色加粗、没有下划线，相邻两项之间一道 14pt 竖线；
 * 横向可滚动，[trailing] 固定在行尾（筛选下拉、「全部已读」）。
 */
public struct PulsoHighlightTabRow<Option: Hashable, Trailing: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Text
    let trailing: Trailing

    @Environment(\.pulsoPalette) private var palette

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> Text,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.options = options
        _selection = selection
        self.label = label
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: PulsoSpace.s2) {
            ScrollView(.horizontal) {
                HStack(spacing: PulsoSpace.s2) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        if index > 0 {
                            Rectangle()
                                .fill(palette.outlineVariant)
                                .frame(width: pulsoHairline, height: 14)
                        }
                        let active = option == selection
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { selection = option }
                        } label: {
                            label(option)
                                .font(.subheadline.weight(active ? .bold : .medium))
                                .foregroundStyle(active ? palette.accent.step(9) : palette.secondaryText)
                                .lineLimit(1)
                                .padding(.horizontal, PulsoSpace.s2)
                                .padding(.vertical, PulsoSpace.s1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, PulsoSpace.s2)
            }
            .scrollIndicators(.hidden)
            trailing
        }
        .padding(.trailing, Trailing.self == EmptyView.self ? 0 : PulsoSpace.s2)
        .background(palette.background)
    }
}
