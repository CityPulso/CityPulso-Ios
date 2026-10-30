import MapLibre
import PulsoLinkCore
import SwiftUI

/** 让地图飞到某处；[id] 变了才飞（Android `recenterRequest` 计数）。 */
struct MapCameraRequest: Equatable {
    var id = 0
    var latitude: Double
    var longitude: Double
    var zoom: Double?
}

/** 地图停下后的中心、估算半径和缩放。 */
struct MapCameraIdle: Equatable {
    let latitude: Double
    let longitude: Double
    let radiusM: Int
    let zoom: Double
}

/** 一个搜索范围圈（Explore 有活动、球馆两个，选点页一个）。 */
struct MapRange: Equatable {
    let source: String
    let layer: String
    let hex: String
    var visible: Bool
    var latitude: Double
    var longitude: Double
    var radiusM: Int
}

/** 地图坐标 ↔ 屏幕坐标，给盖在地图上的 SwiftUI 标记用；[version] 每次相机移动 +1。 */
@MainActor
@Observable
final class LoopMapProjection {
    private(set) var version = 0
    @ObservationIgnored fileprivate weak var mapView: MLNMapView?

    func point(latitude: Double, longitude: Double) -> CGPoint? {
        guard let mapView else { return nil }
        return mapView.convert(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), toPointTo: mapView)
    }

    fileprivate func bump() {
        version &+= 1
    }
}

/**
 * MapLibre 地图（Android 各页里的 `MapView` + style 回调）：OpenFreeMap 样式按深浅色切换，样式加载后再放相机、
 * 3D 建筑和半径圈；不显示 logo、署名和指南针（和 Android 一样）。地图上的标记由调用方用 [projection] 叠上去。
 */
struct LoopMapView: UIViewRepresentable {
    var map: ResolvedMapPreference
    var initialCenter: (latitude: Double, longitude: Double)
    var initialZoom = 13.0
    var camera: MapCameraRequest?
    var ranges: [MapRange] = []
    var projection: LoopMapProjection?
    var onIdle: (MapCameraIdle) -> Void = { _ in }
    var onTap: () -> Void = {}
    /** 长按某点（Explore：在那里标记地点）。 */
    var onLongPress: ((Double, Double) -> Void)?
    /** 用户用手拖 / 缩地图（程序飞过去不算）。 */
    var onGestureMove: () -> Void = {}
    /** 样式加载完，可以开始拉图层数据了。 */
    var onStyleReady: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: styleURL)
        view.backgroundColor = .systemBackground
        view.logoView.isHidden = true
        view.attributionButton.isHidden = true
        view.compassView.isHidden = true
        view.delegate = context.coordinator
        view.setCenter(CLLocationCoordinate2D(latitude: initialCenter.latitude, longitude: initialCenter.longitude), zoomLevel: initialZoom.clamped(to: 3 ... 20), animated: false)
        if !map.mapflat {
            let camera = view.camera
            camera.pitch = 45
            view.setCamera(camera, animated: false)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        view.addGestureRecognizer(longPress)
        context.coordinator.parent = self
        context.coordinator.styleURL = styleURL
        projection?.mapView = view
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.parent
        coordinator.parent = self
        if coordinator.styleURL != styleURL {
            coordinator.styleURL = styleURL
            coordinator.styleReady = false
            view.styleURL = styleURL
        }
        if let camera, camera != coordinator.lastCamera {
            coordinator.lastCamera = camera
            view.setCenter(
                CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
                zoomLevel: (camera.zoom ?? view.zoomLevel).clamped(to: 3 ... 20),
                animated: true
            )
        }
        if previous?.map.mapflat != map.mapflat, view.zoomLevel >= 2.5 {
            let camera = view.camera
            camera.pitch = map.mapflat ? 0 : 45
            view.setCamera(camera, animated: true)
        }
        if coordinator.styleReady, let style = view.style {
            applyLayers(style)
        }
    }

    private var isDark: Bool { colorScheme == .dark }
    private var styleURL: URL { LoopMapStyles.url(light: map.mapLightStyle, dark: map.mapDarkStyle, isDark: isDark) }

    fileprivate func applyLayers(_ style: MLNStyle) {
        Buildings3d.apply(style: style, enabled: map.map3d, light: map.mapLightStyle, dark: map.mapDarkStyle, isDark: isDark)
        for range in ranges {
            MapRangeLayer.ensure(style: style, source: range.source, layer: range.layer, hex: range.hex)
            MapRangeLayer.show(
                style: style, source: range.source, layer: range.layer,
                visible: range.visible, latitude: range.latitude, longitude: range.longitude, radiusM: range.radiusM
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: LoopMapView?
        var styleURL: URL?
        var styleReady = false
        var lastCamera: MapCameraRequest?

        func mapView(_: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            parent?.applyLayers(style)
            parent?.onStyleReady()
        }

        func mapView(_: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated _: Bool) {
            let gestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt]
            if !reason.intersection(gestures).isEmpty { parent?.onGestureMove() }
        }

        func mapViewRegionIsChanging(_: MLNMapView) {
            parent?.projection?.bump()
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated _: Bool) {
            parent?.projection?.bump()
            let center = mapView.centerCoordinate
            let zoom = mapView.zoomLevel
            guard zoom >= 2.5, center.latitude.isFinite, center.longitude.isFinite else { return }
            let bounds = mapView.visibleCoordinateBounds
            let latSpan = max(bounds.ne.latitude - bounds.sw.latitude, 0.001)
            parent?.onIdle(MapCameraIdle(
                latitude: center.latitude,
                longitude: center.longitude,
                radiusM: estimateRadiusM(latitude: center.latitude, latSpanDegrees: latSpan),
                zoom: zoom
            ))
        }

        @objc func tapped() {
            parent?.onTap()
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView = recognizer.view as? MLNMapView, let onLongPress = parent?.onLongPress else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            onLongPress(coordinate.latitude, coordinate.longitude)
        }
    }
}
