import CoreGraphics
import H4Kit
import QuartzCore
import UIKit

/// The walk frames of an actor in one direction: the `walk` action of `adv_actor.<name>` (sequence of the direction), one
/// image per `frame` layer, with the owner flag drawn on it. Offsets are canvas pixels from the cell anchor.
struct WalkSprite {
    struct Frame {
        let image: CGImage
        let dx: Int, dy: Int
    }

    let frames: [Frame]

    /// Direction names in file order (movement numbering 0...7).
    static let directions = ["ne", "e", "se", "s", "sw", "w", "nw", "n"]
    static let colours = ["Red", "Blue", "Green", "Orange", "Purple", "Teal"]

    private struct Reader {
        let data: Data
        var offset = 0
        mutating func u8() -> Int? { guard offset < data.count else { return nil }; defer { offset += 1 }; return Int(data[data.startIndex + offset]) }
        mutating func u16() -> Int? {
            guard let a = u8(), let b = u8() else { return nil }
            return a | b << 8
        }
        mutating func i32() -> Int? {
            guard let a = u16(), let b = u16() else { return nil }
            return Int(Int32(truncatingIfNeeded: a | b << 16))
        }
        mutating func string() -> String? {
            guard let n = u16(), offset + n <= data.count else { return nil }
            defer { offset += n }
            return String(decoding: data[(data.startIndex + offset)..<(data.startIndex + offset + n)], as: UTF8.self)
        }
    }

    /// Sequence names of the `walk` action (8 directions) and the flag attach point of `adv_actor.<name>`.
    static func walkSequences(actor: String, store: H4ResourceStore) -> (sequences: [String], flag: (x: Int, y: Int))? {
        guard let data = try? store.data(for: "adv_actor.\(actor).h4d") else { return nil }
        var r = Reader(data: data)
        guard r.u16() != nil, r.u8() != nil, r.u16() != nil, r.u16() != nil, r.u16() != nil, let n = r.u16() else { return nil }
        var walk: [String]?
        for _ in 0..<n {
            guard let name = r.string(), r.u8() != nil else { return nil }
            var seqs: [String] = []
            for _ in 0..<8 { guard let s = r.string() else { return nil }; seqs.append(s) }
            if name == "walk" { walk = seqs }
        }
        guard let walk, let x0 = r.i32(), let y0 = r.i32() else { return nil }
        return (walk, (x0, y0))
    }

    /// `actor` without the `adv_actor.` prefix; `direction` 0...7; `owner` 0...5 gets a flag.
    static func load(actor: String, direction: Int, owner: Int, store: H4ResourceStore) -> WalkSprite? {
        guard let info = walkSequences(actor: actor, store: store), info.sequences.indices.contains(direction),
              let seqData = try? store.data(for: "actor_sequence.\(info.sequences[direction]).h4d"),
              let seq = try? H4ActorSequence(data: seqData) else { return nil }
        var flag: (layer: H4Layer, hx: Int, hy: Int)?
        if (0...5).contains(owner), let data = try? store.data(for: "animation.Flags.\(colours[owner]).h4d"),
           let a = try? H4Animation(data: data), let l = a.frames.layers.first {
            flag = (l, Int(a.extra?.x ?? 0), Int(a.extra?.y ?? 0))
        }
        let ox = Int(seq.originX), oy = Int(seq.originY)
        var frames: [Frame] = []
        for body in seq.frames.layers where body.name.hasPrefix("frame") && !body.isEmpty {
            // rectangles relative to the anchor
            var x0 = ox + body.left, y0 = oy + body.top, x1 = ox + body.right, y1 = oy + body.bottom
            var fx = 0, fy = 0
            if let flag {
                fx = info.flag.x - flag.hx + flag.layer.left
                fy = info.flag.y - flag.hy + flag.layer.top
                x0 = min(x0, fx); y0 = min(y0, fy); x1 = max(x1, fx + flag.layer.width); y1 = max(y1, fy + flag.layer.height)
            }
            var canvas = H4RGBAImage(width: x1 - x0, height: y1 - y0, pixels: [UInt8](repeating: 0, count: (x1 - x0) * (y1 - y0) * 4))
            body.draw(into: &canvas, originX: ox - x0, originY: oy - y0)
            if let flag { flag.layer.draw(into: &canvas, originX: fx - flag.layer.left - x0, originY: fy - flag.layer.top - y0) }
            if let image = canvas.cgImage() { frames.append(Frame(image: image, dx: x0, dy: y0)) }
        }
        return frames.isEmpty ? nil : WalkSprite(frames: frames)
    }
}

/// An overlay sprite that walks along cells above the tiles (CALayer in the zoomed content view, driven by a display
/// link): 0.25 s per cell, 10 frames per second, the camera follows.
@MainActor
final class WalkOverlay: NSObject {
    static let secondsPerCell = 0.25
    static let framesPerSecond = 10.0

    private let store: H4ResourceStore
    private let mapSize: Int
    private var sprites: [String: WalkSprite] = [:]
    private let layer = CALayer()
    private var link: CADisplayLink?
    private weak var host: MapScrollView?
    private var actor = "", owner = 6
    private var cells: [H4MoveCell] = []
    private var started = CACurrentMediaTime()
    private var completion: (() -> Void)?
    private(set) var isRunning = false

    init(store: H4ResourceStore, mapSize: Int) {
        self.store = store
        self.mapSize = mapSize
        super.init()
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.zPosition = 1000
        layer.isHidden = true
    }

    private func sprite(direction: Int) -> WalkSprite? {
        let key = "\(actor)|\(direction)|\(owner)"
        if let s = sprites[key] { return s }
        let s = WalkSprite.load(actor: actor, direction: direction, owner: owner, store: store)
        if let s { sprites[key] = s }
        return s
    }

    private func anchor(_ c: H4MoveCell) -> (x: Double, y: Double) {
        (Double(32 * (c.c - c.r) + 32 * mapSize), Double(16 * (c.r + c.c)))
    }

    /// Walks `actor` (name without the `adv_actor.` prefix) over `cells`; false when there is nothing to show (the caller
    /// then finishes without animation).
    func run(actor: String, owner: Int, cells: [H4MoveCell], host: MapScrollView, completion: @escaping () -> Void) -> Bool {
        stop()
        guard cells.count >= 2 else { return false }
        self.actor = actor; self.owner = owner; self.cells = cells; self.host = host; self.completion = completion
        guard sprite(direction: H4PathArrows.direction(from: cells[0], to: cells[1]) ?? 2) != nil else { return false }
        host.overlayHost.addSublayer(layer)
        layer.isHidden = false
        started = CACurrentMediaTime()
        isRunning = true
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        tick()
        return true
    }

    @objc private func tick() {
        guard isRunning, let host else { return }
        let steps = cells.count - 1
        let t = CACurrentMediaTime() - started
        let total = Double(steps) * Self.secondsPerCell
        if t >= total {
            place(host: host, seg: steps - 1, frac: 1, t: t)
            link?.invalidate(); link = nil
            isRunning = false
            let done = completion
            completion = nil
            done?()
            return
        }
        let seg = min(Int(t / Self.secondsPerCell), steps - 1)
        place(host: host, seg: seg, frac: (t - Double(seg) * Self.secondsPerCell) / Self.secondsPerCell, t: t)
    }

    private func place(host: MapScrollView, seg: Int, frac: Double, t: Double) {
        let a = anchor(cells[seg]), b = anchor(cells[seg + 1])
        let x = a.x + (b.x - a.x) * frac, y = a.y + (b.y - a.y) * frac
        let dir = H4PathArrows.direction(from: cells[seg], to: cells[seg + 1]) ?? 2
        guard let s = sprite(direction: dir) else { return }
        let f = s.frames[Int(t * Self.framesPerSecond) % s.frames.count]
        let p0 = host.layerPoint(canvasX: x + Double(f.dx), canvasY: y + Double(f.dy))
        let p1 = host.layerPoint(canvasX: x + Double(f.dx + f.image.width), canvasY: y + Double(f.dy + f.image.height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = f.image
        layer.frame = CGRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y)
        CATransaction.commit()
        host.centre(onCanvasX: x, y: y + 16)
    }

    /// Stops the animation at once (no completion call) and hides the sprite.
    func stop() {
        link?.invalidate(); link = nil
        isRunning = false
        completion = nil
        layer.isHidden = true
        layer.removeFromSuperlayer()
    }

    /// Hides the sprite after `delay` seconds (time for the refreshed tiles to appear under it).
    func hide(after delay: Double) {
        let l = layer
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isRunning else { return }
            l.isHidden = true
            l.removeFromSuperlayer()
        }
    }
}
