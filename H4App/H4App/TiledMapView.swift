import H4Kit
import QuartzCore
import SwiftUI
import UIKit

/// Lets code outside the view (the DEBUG auto-tour) drive the zoom of the scroll view.
final class MapViewportHandle {
    fileprivate weak var scrollView: MapScrollView?
    var isAttached: Bool { scrollView != nil }
    /// One device pixel per canvas pixel, centred.
    func zoomToNativePixels() { scrollView?.zoomToNative() }
}

/// The map: a UIScrollView (pan, inertia, pinch) around one view whose layer is a CATiledLayer. Each tile is rendered
/// by H4Kit at the scale that matches the level of detail the system asks for (1, 2, 4 or 8).
struct TiledMapView: UIViewRepresentable {
    let session: MapSession
    let level: Int
    let displayScale: CGFloat
    var viewport: MapViewportHandle?
    var onLongPress: (MapCellInfo?) -> Void

    func makeUIView(context: Context) -> MapScrollView {
        let view = MapScrollView(session: session, level: level, screenScale: displayScale)
        view.onLongPress = onLongPress
        viewport?.scrollView = view
        return view
    }

    func updateUIView(_ view: MapScrollView, context: Context) {
        view.onLongPress = onLongPress
        viewport?.scrollView = view
        view.setLevel(level)
    }
}

/// Tile source read by the (background) draw calls of the layer; replaced as a whole when the level changes.
final class TileSource: @unchecked Sendable {
    let session: MapSession
    let level: Int
    let canvasPerPoint: Double
    init(session: MapSession, level: Int, canvasPerPoint: Double) {
        self.session = session; self.level = level; self.canvasPerPoint = canvasPerPoint
    }
}

final class MapContentView: UIView {
    override class var layerClass: AnyClass { MapTiledLayer.self }
    private let lock = NSLock()
    private nonisolated(unsafe) var source: TileSource?

    var tiledLayer: MapTiledLayer { layer as! MapTiledLayer }

    func setSource(_ new: TileSource) {
        lock.lock(); source = new; lock.unlock()
    }

    private nonisolated func currentSource() -> TileSource? {
        lock.lock(); defer { lock.unlock() }
        return source
    }

    /// Called by CATiledLayer on background threads, once per tile; `rect` is the tile in layer points.
    nonisolated override func draw(_ rect: CGRect) {
        guard let source = currentSource(), let ctx = UIGraphicsGetCurrentContext() else { return }
        let session = source.session
        let request = session.levels[source.level].canvas.tileRequest(
            x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
            canvasPerPoint: source.canvasPerPoint, deviceScale: abs(Double(ctx.ctm.a)))
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let image = try session.tileImage(level: source.level, request: request)
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            let d = request.destination
            UIImage(cgImage: image).draw(in: CGRect(x: d.x, y: d.y, width: d.width, height: d.height))
            TileStats.shared.record(ms: Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6, scale: request.scale)
        } catch {
            TileStats.shared.recordError("\(error)")
        }
    }
}

final class MapTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }
}

final class MapScrollView: UIScrollView, UIScrollViewDelegate {
    private let session: MapSession
    private let content = MapContentView()
    private var level: Int
    private let screenScale: CGFloat
    private var lastBounds = CGRect.zero
    var onLongPress: ((MapCellInfo?) -> Void)?

    /// Zoom at which the whole content rect fits the view.
    private var fitZoom: CGFloat = 1

    init(session: MapSession, level: Int, screenScale: CGFloat) {
        self.session = session
        self.level = level
        self.screenScale = screenScale > 0 ? screenScale : 2
        super.init(frame: .zero)
        backgroundColor = .black
        delegate = self
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .normal

        // One layer point = `screenScale` canvas pixels, so zoom 1 shows one canvas pixel per device pixel.
        let rect = session.contentRect
        content.frame = CGRect(x: 0, y: 0, width: CGFloat(rect.width) / screenScale, height: CGFloat(rect.height) / screenScale)
        let tiled = content.tiledLayer
        tiled.tileSize = CGSize(width: 512, height: 512)
        tiled.levelsOfDetail = 4            // magnifications 1, 1/2, 1/4, 1/8 → render scales 1, 2, 4, 8
        tiled.levelsOfDetailBias = 1        // plus 2x for the maximum zoom
        tiled.contentsScale = screenScale
        content.backgroundColor = .black
        content.setSource(TileSource(session: session, level: level, canvasPerPoint: Double(screenScale)))
        addSubview(content)
        contentSize = content.frame.size

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.45
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setLevel(_ new: Int) {
        guard new != level, session.levels.indices.contains(new) else { return }
        level = new
        content.setSource(TileSource(session: session, level: new, canvasPerPoint: Double(screenScale)))
        content.tiledLayer.setNeedsDisplay()
        onLongPress?(nil)
        zoomScale = minimumZoomScale
        centreContent()
    }

    // MARK: layout and zoom

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBounds.size, bounds.width > 0, bounds.height > 0 {
            let wasFitted = lastBounds.isEmpty || zoomScale <= fitZoom * 1.001
            lastBounds = bounds
            updateZoomLimits()
            if wasFitted { zoomScale = fitZoom }
            else { zoomScale = min(max(zoomScale, minimumZoomScale), maximumZoomScale) }
        }
        centreContent()
    }

    private func updateZoomLimits() {
        let size = content.bounds.size
        fitZoom = min(bounds.width / size.width, bounds.height / size.height)
        minimumZoomScale = fitZoom
        maximumZoomScale = max(2, fitZoom)
    }

    /// Keeps content smaller than the view centred.
    private func centreContent() {
        let size = content.frame.size
        let dx = max(0, (bounds.width - size.width) / 2), dy = max(0, (bounds.height - size.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centreContent() }

    func zoomToNative() {
        let target = min(max(1, minimumZoomScale), maximumZoomScale)
        zoom(to: CGPoint(x: content.bounds.midX, y: content.bounds.midY), scale: target, animated: false)
        // Used by the DEBUG tour: force a real redraw at this zoom, even when CATiledLayer could reuse
        // tiles of the same level of detail (small maps whose fit view is already at that level).
        content.tiledLayer.setNeedsDisplay()
    }

    private func zoom(to point: CGPoint, scale: CGFloat, animated: Bool) {
        let w = bounds.width / scale, h = bounds.height / scale
        zoom(to: CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h), animated: animated)
    }

    // MARK: gestures

    @objc private func doubleTap(_ g: UITapGestureRecognizer) {
        if zoomScale > fitZoom * 1.05 {
            setZoomScale(fitZoom, animated: true)
        } else {
            zoom(to: g.location(in: content), scale: min(maximumZoomScale, max(1, fitZoom * 4)), animated: true)
        }
    }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = g.location(in: content)
        let rect = session.contentRect
        let x = Double(rect.x) + Double(p.x) * Double(screenScale)
        let y = Double(rect.y) + Double(p.y) * Double(screenScale)
        onLongPress?(session.cellInfo(level: level, canvasX: x, canvasY: y))
    }
}
