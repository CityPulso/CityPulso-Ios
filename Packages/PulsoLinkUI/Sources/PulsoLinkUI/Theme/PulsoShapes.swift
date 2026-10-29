import PulsoLinkCore
import SwiftUI

/**
 * Radix radius scale (`--radius-1..6` = 3/4/6/8/12/16 px × factor)，与 PulsoLink-Package `themes/index.css` 一致。
 *
 * | tier            | factor | pill controls |
 * |-----------------|--------|---------------|
 * | NONE (Linux)    | 0      | no            |
 * | SMALL (Android) | 0.75   | no            |
 * | MEDIUM (Other)  | 1      | no            |
 * | LARGE (Windows) | 1.5    | no            |
 * | FULL (iOS)      | 1.5    | **yes**       |
 *
 * FULL 只把 `--radius-full` 变成胶囊；1–6 档与 LARGE 相同，面板、卡片、对话框在 iOS 档不会变得过圆。
 */
public struct PulsoRadii: Sendable, Equatable {
    public let r1: CGFloat
    public let r2: CGFloat
    public let r3: CGFloat
    public let r4: CGFloat
    public let r5: CGFloat
    public let r6: CGFloat
    public let isFull: Bool

    public init(radius: ThemeRadius) {
        let factor: CGFloat = switch radius {
        case .none: 0
        case .small: 0.75
        case .medium: 1
        case .large, .full: 1.5
        }
        r1 = 3 * factor
        r2 = 4 * factor
        r3 = 6 * factor
        r4 = 8 * factor
        r5 = 12 * factor
        r6 = 16 * factor
        isFull = radius == .full
    }
}

/**
 * 语义形状：按元素「是什么」选，不写圆角数字。
 *
 * iOS 档变胶囊（紧凑控件，WEB `max(--radius-N, --radius-full)`）：control / chip / avatar。
 * 永不变胶囊（面板，WEB `--radius-4…6`）：card / dialog / sheet / bubble / pin / textArea / inner。
 */
public struct PulsoShapeSet: Sendable, Equatable {
    public let radii: PulsoRadii

    public init(radius: ThemeRadius) {
        radii = PulsoRadii(radius: radius)
    }

    /** 按钮、单行输入框、分段控件轨道、日期 / 筛选 chip、标签、徽标。 */
    public var control: AnyShape { pillOr(radii.r3) }
    /** 小色块与密集 chip（WEB `--radius-chip`）。 */
    public var chip: AnyShape { pillOr(radii.r2) }
    /** iOS 档为圆形。 */
    public var avatar: AnyShape { pillOr(radii.r4) }
    /** 卡片与列表面板（iOS 档 = r6）。 */
    public var card: RoundedRectangle { RoundedRectangle(cornerRadius: radii.isFull ? radii.r6 : radii.r4, style: .continuous) }
    /** 对话框与下拉菜单。 */
    public var dialog: RoundedRectangle { RoundedRectangle(cornerRadius: radii.r4, style: .continuous) }
    /** 底部弹层：只有上方两角带圆角。 */
    public var sheet: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radii.r4, topTrailingRadius: radii.r4, style: .continuous)
    }
    /** 顶部弹层：只有下方两角带圆角。 */
    public var topSheet: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: radii.r4, bottomTrailingRadius: radii.r4, style: .continuous)
    }
    public var bubble: RoundedRectangle { RoundedRectangle(cornerRadius: radii.r5, style: .continuous) }
    public var pin: RoundedRectangle { RoundedRectangle(cornerRadius: radii.r3, style: .continuous) }
    public var textArea: RoundedRectangle { RoundedRectangle(cornerRadius: radii.r3, style: .continuous) }
    /** 卡片里嵌套的东西（缩略图、格子）。 */
    public var inner: RoundedRectangle { RoundedRectangle(cornerRadius: radii.r2, style: .continuous) }
    /** 分段控件的滑块，比 [control] 轨道内缩 2pt。 */
    public var segmentThumb: AnyShape { pillOr(radii.r2) }

    private func pillOr(_ radius: CGFloat) -> AnyShape {
        radii.isFull ? AnyShape(Capsule(style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
