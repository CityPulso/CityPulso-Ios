import Foundation
import MapLibre
import PulsoLinkCore
import UIKit

/** OpenFreeMap 样式地址（Android `LoopMapStyles`，WEB `MAP_STYLE_URLS`）。 */
enum LoopMapStyles {
    private static let cdn = "https://tiles.openfreemap.org/styles"

    static func url(light: MapLightColor, dark: MapDarkColor, isDark: Bool) -> URL {
        URL(string: "\(cdn)/\(isDark ? dark.rawValue : light.rawValue)")!
    }
}

/**
 * OpenFreeMap / OpenMapTiles 的 3D 建筑（Android `Buildings3d`，Package `buildings3d.ts`）：
 * 在矢量源上挂 fill-extrusion，不去开关样式里不一定有的 building 层。
 */
enum Buildings3d {
    static let layerId = "explorer-buildings-3d"
    private static let sourceId = "openmaptiles"
    private static let sourceLayer = "building"
    private static let minZoom: Float = 15

    static func colorHex(light: MapLightColor, dark: MapDarkColor, isDark: Bool) -> String {
        if isDark {
            switch dark {
            case .dark: "#1e2535"
            case .fiord: "#2d3a4a"
            }
        } else {
            switch light {
            case .positron: "#cac6be"
            case .bright: "#c4c8c0"
            case .liberty: "#b8b4ac"
            }
        }
    }

    static func apply(style: MLNStyle, enabled: Bool, light: MapLightColor, dark: MapDarkColor, isDark: Bool) {
        let existing = style.layer(withIdentifier: layerId) as? MLNFillExtrusionStyleLayer
        guard enabled else {
            existing?.isVisible = false
            return
        }
        guard let source = style.source(withIdentifier: sourceId) else { return }
        let color = NSExpression(forConstantValue: UIColor(hex: colorHex(light: light, dark: dark, isDark: isDark)))
        if let existing {
            existing.fillExtrusionColor = color
            existing.isVisible = true
            return
        }
        let layer = MLNFillExtrusionStyleLayer(identifier: layerId, source: source)
        layer.sourceLayerIdentifier = sourceLayer
        layer.fillExtrusionColor = color
        layer.fillExtrusionHeight = NSExpression(format: "mgl_coalesce({render_height, height, 5})")
        layer.fillExtrusionBase = NSExpression(format: "mgl_coalesce({render_min_height, min_height, 0})")
        layer.fillExtrusionOpacity = NSExpression(forConstantValue: 0.85)
        layer.minimumZoomLevel = minZoom
        style.addLayer(layer)
    }
}

/** 搜索半径的圆（Android `MapRangeLayer`：Explore 图层、选点页共用）。填充 20% 透明。 */
enum MapRangeLayer {
    static func ensure(style: MLNStyle, source: String, layer: String, hex: String) {
        if style.source(withIdentifier: source) == nil {
            style.addSource(MLNShapeSource(identifier: source, shape: nil, options: nil))
        }
        if style.layer(withIdentifier: layer) == nil, let shapeSource = style.source(withIdentifier: source) {
            let fill = MLNFillStyleLayer(identifier: layer, source: shapeSource)
            fill.fillColor = NSExpression(forConstantValue: UIColor(hex: hex).withAlphaComponent(0.2))
            fill.fillOutlineColor = NSExpression(forConstantValue: UIColor(hex: hex))
            fill.isVisible = false
            style.addLayer(fill)
        }
    }

    static func show(style: MLNStyle, source: String, layer: String, visible: Bool, latitude: Double, longitude: Double, radiusM: Int) {
        guard let shapeSource = style.source(withIdentifier: source) as? MLNShapeSource else { return }
        if visible {
            var ring = polygon(latitude: latitude, longitude: longitude, radiusM: radiusM)
            shapeSource.shape = MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
        } else {
            shapeSource.shape = nil
        }
        style.layer(withIdentifier: layer)?.isVisible = visible
    }

    /** 以该点为圆心、[radiusM] 米为半径的 64 边形。 */
    static func polygon(latitude: Double, longitude: Double, radiusM: Int) -> [CLLocationCoordinate2D] {
        let points = 64
        let earth = 6_371_000.0
        let distance = Double(radiusM) / earth
        let lat1 = latitude * .pi / 180
        let lng1 = longitude * .pi / 180
        var ring: [CLLocationCoordinate2D] = (0 ..< points).map { index in
            let bearing = 2 * Double.pi * Double(index) / Double(points)
            let lat2 = asin(sin(lat1) * cos(distance) + cos(lat1) * sin(distance) * cos(bearing))
            let lng2 = lng1 + atan2(sin(bearing) * sin(distance) * cos(lat1), cos(distance) - sin(lat1) * sin(lat2))
            return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lng2 * 180 / .pi)
        }
        ring.append(ring[0])
        return ring
    }
}

/** 可见范围对应的搜索半径（Android `ExploreViewModel.estimateRadiusM`）：纬度跨度的一半，50 米到 50 公里。 */
func estimateRadiusM(latitude: Double, latSpanDegrees: Double) -> Int {
    let metersPerDegree = 111_320.0 * max(cos(latitude * .pi / 180), 0.2)
    return max(50, min(50_000, Int(latSpanDegrees * metersPerDegree / 2)))
}

extension UIColor {
    /** `#RRGGBB`。 */
    convenience init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
