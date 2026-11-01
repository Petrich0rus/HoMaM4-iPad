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

/// Lets the game model (play screen) reach the scroll view: tap callback, tile invalidation, the walk overlay host.
final class MapGameHooks {
    fileprivate weak var scrollView: MapScrollView?
    /// A single tap on a map cell: (level, row, column).
    var onTap: ((Int, Int, Int) -> Void)?
    var isAttached: Bool { scrollView != nil }

    /// Redraws the tiles under the given rectangles (scale-1 canvas pixels). Main thread.
    func invalidate(canvasRects: [CGRect]) { scrollView?.invalidate(canvasRects: canvasRects) }
    /// The view that hosts the walk overlay.
    var host: MapScrollView? { scrollView }
}

/// The map: a UIScrollView (pan, inertia, pinch) around one view whose layer is a CATiledLayer. Each tile is rendered
/// by H4Kit at the scale that matches the level of detail the system asks for (1, 2, 4 or 8).
struct TiledMapView: UIViewRepresentable {
    let session: MapSession
    let level: Int
    let displayScale: CGFloat
    var viewport: MapViewportHandle?
    /// Present on the play screen: single taps are reported and the step-1 double-tap zoom is off.
    var hooks: MapGameHooks?
    var onLongPress: (MapCellInfo?) -> Void

    func makeUIView(context: Context) -> MapScrollView {
        let view = MapScrollView(session: session, level: level, screenScale: displayScale, hooks: hooks)
        view.onLongPress = onLongPress
        viewport?.scrollView = view
        hooks?.scrollView = view
        return view
    }

    func updateUIView(_ view: MapScrollView, context: Context) {
        view.onLongPress = onLongPress
        viewport?.scrollView = view
        hooks?.scrollView = view
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
        let generation = session.generation
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
        // The game replaced the draw list while this tile was being drawn: draw it again.
        if session.generation != generation {
            DispatchQueue.main.async { [weak self] in self?.tiledLayer.setNeedsDisplay(rect) }
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
    private let hooks: MapGameHooks?
    var currentLevel: Int { level }
    /// Layer hosting the walk overlay sprite (inside the zoomed content).
    var overlayHost: CALayer { content.layer }

    /// Zoom at which the whole content rect fits the view.
    private var fitZoom: CGFloat = 1

    init(session: MapSession, level: Int, screenScale: CGFloat, hooks: MapGameHooks? = nil) {
        self.session = session
        self.hooks = hooks
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

        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.45
        addGestureRecognizer(press)
        if hooks != nil {
            // Play screen: two quick taps are two commands (plan, then move), so no double-tap zoom here.
            let tap = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
            tap.require(toFail: press)
            addGestureRecognizer(tap)
        } else {
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            addGestureRecognizer(double)
        }
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

    // MARK: game support

    /// Layer-space point (points of the content view) of a scale-1 canvas point.
    func layerPoint(canvasX: Double, canvasY: Double) -> CGPoint {
        let rect = session.contentRect
        return CGPoint(x: (canvasX - Double(rect.x)) / Double(screenScale), y: (canvasY - Double(rect.y)) / Double(screenScale))
    }

    func invalidate(canvasRects: [CGRect]) {
        for r in canvasRects {
            let a = layerPoint(canvasX: r.minX, canvasY: r.minY), b = layerPoint(canvasX: r.maxX, canvasY: r.maxY)
            content.tiledLayer.setNeedsDisplay(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        }
    }

    /// Scrolls so that the canvas point is in the middle of the view (clamped to the content).
    func centre(onCanvasX x: Double, y: Double) {
        let p = layerPoint(canvasX: x, canvasY: y)
        let z = zoomScale
        let minX = -contentInset.left, maxX = contentSize.width - bounds.width + contentInset.right
        let minY = -contentInset.top, maxY = contentSize.height - bounds.height + contentInset.bottom
        let target = CGPoint(x: min(max(p.x * z - bounds.width / 2, minX), max(minX, maxX)),
                             y: min(max(p.y * z - bounds.height / 2, minY), max(minY, maxY)))
        setContentOffset(target, animated: false)
    }

    @objc private func singleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let hooks else { return }
        let p = g.location(in: content)
        let rect = session.contentRect
        let x = Double(rect.x) + Double(p.x) * Double(screenScale)
        let y = Double(rect.y) + Double(p.y) * Double(screenScale)
        guard let cell = session.levels[level].canvas.cell(atX: x, y: y) else { return }
        hooks.onTap?(level, cell.row, cell.column)
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
