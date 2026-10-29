import Foundation

/* 地图域枚举——wire 值与 PulsoLink-Package `enums/map.ts` 逐一对齐。 */

/** 浅色外观下可选的地图样式。 */
public enum MapLightColor: String, WireEnum {
    case positron, bright, liberty

    public static let fallback: MapLightColor = .positron
}

/** 深色外观下可选的地图样式。 */
public enum MapDarkColor: String, WireEnum {
    case dark, fiord

    public static let fallback: MapDarkColor = .dark
}

/** 定位点颜色字段。 */
public enum LocationMarkerColorKey: String, WireEnum {
    case ring, dot, border

    public static let fallback: LocationMarkerColorKey = .ring
}

/** 定位头像颜色字段。 */
public enum LocationMarkerAvatarColorKey: String, WireEnum {
    case bg, border

    public static let fallback: LocationMarkerAvatarColorKey = .bg
}

/** 地图/几何区域形状 wire 枚举。 */
public enum RegionType: String, WireEnum {
    case none, circle, line, polygon

    public static let fallback: RegionType = .none
}

/** 地图画布展示模式（3d explorer vs flat）。 */
public enum MapViewMode: String, WireEnum {
    case explorer, flat

    public static let fallback: MapViewMode = .explorer
}
