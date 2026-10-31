import SwiftUI

/** 空列表的图标类型（Android `PulsoEmptyStyle`，对齐 WEB EmptySceneVariantEnum）。 */
public enum PulsoEmptyStyle: Sendable {
    /** 通用空列表。 */
    case abstract
    /** 日程 / 活动 / 收款清单。 */
    case calendar
    /** 聊天 / 社交。 */
    case campfire
    /** 尚未开放。 */
    case comingSoon

    var systemImage: String {
        switch self {
        case .abstract: "tray"
        case .calendar: "calendar"
        case .campfire: "flame"
        case .comingSoon: "sparkles"
        }
    }
}

/**
 * 统一空状态（Android `PulsoEmptyState`）：96pt 强调色 step3 圆底里一个 step9 图标（缓慢呼吸），
 * 半粗标题、次要字色说明（最宽 280），可选主按钮（实心）和次按钮（灰色描边）。在给它的空间里居中。
 */
public struct PulsoEmptyState<Actions: View>: View {
    let title: Text
    let description: Text?
    let style: PulsoEmptyStyle
    let actions: Actions

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    public init(
        _ title: Text,
        description: Text? = nil,
        style: PulsoEmptyStyle = .abstract,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.description = description
        self.style = style
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Image(systemName: style.systemImage)
                .font(.system(size: 30))
                .foregroundStyle(palette.accent.step(9))
                .frame(width: 96, height: 96)
                .background(palette.accent.step(3), in: Circle())
                .scaleEffect(breathing ? 1 : 0.92)
                .accessibilityHidden(true)
            title
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.text)
                .padding(.top, PulsoSpace.s5)
            if let description {
                description
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: 280)
                    .padding(.top, PulsoSpace.s2)
            }
            if Actions.self != EmptyView.self {
                HStack(spacing: PulsoSpace.s2) { actions }
                    .padding(.top, PulsoSpace.s5)
            }
        }
        .multilineTextAlignment(.center)
        .padding(PulsoSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/**
 * 从几个值里选一个（Android `PulsoMenuSelect`，WEB MenuSelect）：灰色柔和的控件显示当前值和下拉箭头，
 * 点开系统菜单，当前项打勾。高度与按钮 / 输入框同档。
 */
public struct PulsoMenuSelect<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let size: PulsoControlSize?
    let label: (Option) -> Text

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var pageSize

    public init(_ options: [Option], selection: Binding<Option>, size: PulsoControlSize? = nil, label: @escaping (Option) -> Text) {
        self.options = options
        _selection = selection
        self.size = size
        self.label = label
    }

    public var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options, id: \.self) { label($0).tag($0) }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: PulsoSpace.s1) {
                label(selection)
                    .font(.body)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(palette.gray.step(12))
            .padding(.horizontal, PulsoSpace.s3)
            .frame(height: (size ?? pageSize).height)
            .background(palette.gray.step(3), in: palette.controlShape)
        }
        .buttonStyle(.plain)
    }
}
