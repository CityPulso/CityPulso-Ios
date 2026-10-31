import NukeUI
import SwiftUI

/**
 * 头像（对应 Android `PulsoAvatar`）：有 [url] 时用 Nuke 加载，否则显示 [systemImage]，再退到 [fallbackText] 的首字。
 * 形状跟主题圆角档位（iOS 档是正圆，其余是 r4 圆角方）；底色强调色 step3，占位字 / 图标 step11。
 */
public struct PulsoAvatar: View {
    @Environment(\.pulsoPalette) private var palette

    private let url: URL?
    private let size: CGFloat
    private let systemImage: String?
    private let fallbackText: String?

    public init(url: URL?, size: CGFloat, systemImage: String? = nil, fallbackText: String? = nil) {
        self.url = url
        self.size = size
        self.systemImage = systemImage
        self.fallbackText = fallbackText
    }

    public var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(palette.accent.step(3))
        .clipShape(palette.avatarShape)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.45))
                .foregroundStyle(palette.accent.step(11))
        } else {
            Text(String((fallbackText ?? "?").prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(palette.accent.step(11))
        }
    }
}

/** 远程图片，按 [contentMode] 填满给定的框；加载中和失败显示系统填充色。 */
public struct PulsoRemoteImage: View {
    private let url: URL?
    private let contentMode: ContentMode

    public init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    public var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
    }
}
