import PulsoLinkCore
import SwiftUI

/**
 * 控件高度档位（输入框 / 按钮共用，同档同高）：
 * - small：贴着二级 tab 行的下拉菜单 / 筛选按钮
 * - compact：默认输入框高度
 * - comfortable：compact 与 prominent 的中间值（登录/注册）
 * - prominent：欢迎页大按钮
 */
public enum PulsoControlSize: Sendable {
    case small, compact, comfortable, prominent
}

/**
 * 尺寸 tokens（对应 Radix `scaling`）：基准值 × scaling 系数，经环境值 `pulsoDimensions` 全局提供。
 *
 * - 间距 `space1..space9` 与 WEB `--space-1..9` 同刻度（4 / 8 / 12 / 16 / 24 / 32 / 40 / 48 / 64），
 *   `spaceHalf` = 2，只用于紧贴的文字与图标之间。
 * - 图标 `icon1..icon5` = 12 / 16 / 20 / 24 / 32。
 * - 头像 `avatar1..avatar7` = 24 / 32 / 40 / 48 / 64 / 80 / 96（WEB Radix Avatar size 1–7）。
 * - 组件固有几何（票根宽、pin 尺寸、封面高度等）不走这里，写成所在文件顶部的具名常量。
 */
public struct PulsoDimensions: Sendable, Equatable {
    public let controlHeightSmall: CGFloat
    public let controlHeightMedium: CGFloat
    public let controlHeightLarge: CGFloat
    public let controlHeightProminent: CGFloat
    public let spaceHalf: CGFloat
    public let space1: CGFloat
    public let space2: CGFloat
    public let space3: CGFloat
    public let space4: CGFloat
    public let space5: CGFloat
    public let space6: CGFloat
    public let space7: CGFloat
    public let space8: CGFloat
    public let space9: CGFloat
    public let icon1: CGFloat
    public let icon2: CGFloat
    public let icon3: CGFloat
    public let icon4: CGFloat
    public let icon5: CGFloat
    public let avatar1: CGFloat
    public let avatar2: CGFloat
    public let avatar3: CGFloat
    public let avatar4: CGFloat
    public let avatar5: CGFloat
    public let avatar6: CGFloat
    public let avatar7: CGFloat

    public init(scaling: ThemeScaling) {
        let f = CGFloat(scaling.factor)
        controlHeightSmall = 32 * f
        controlHeightMedium = 40 * f
        controlHeightLarge = 48 * f
        controlHeightProminent = 56 * f
        spaceHalf = 2 * f
        space1 = 4 * f
        space2 = 8 * f
        space3 = 12 * f
        space4 = 16 * f
        space5 = 24 * f
        space6 = 32 * f
        space7 = 40 * f
        space8 = 48 * f
        space9 = 64 * f
        icon1 = 12 * f
        icon2 = 16 * f
        icon3 = 20 * f
        icon4 = 24 * f
        icon5 = 32 * f
        avatar1 = 24 * f
        avatar2 = 32 * f
        avatar3 = 40 * f
        avatar4 = 48 * f
        avatar5 = 64 * f
        avatar6 = 80 * f
        avatar7 = 96 * f
    }

    /** 按 [PulsoControlSize] 取输入框/按钮统一高度。 */
    public func controlHeight(_ size: PulsoControlSize) -> CGFloat {
        switch size {
        case .small: controlHeightSmall
        case .compact: controlHeightMedium
        case .comfortable: controlHeightLarge
        case .prominent: controlHeightProminent
        }
    }
}

/** 边框与分隔线宽度：不随 scaling 变化。 */
public let pulsoHairline: CGFloat = 0.5

/** 选中 / 强调描边（选中卡片、头像外圈、pin 描边）。 */
public let pulsoStrokeEmphasis: CGFloat = 1
