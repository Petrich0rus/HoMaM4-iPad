import Foundation

// Slice 6a-O: objects drawn over the terrain canvas of a map region (spec `SPEC_objects_render.md`).

/// One sprite layer prepared for blitting: palette indices and 8-bit alpha, row spans.
public final class H4ObjectLayerPixels: @unchecked Sendable {
    public let width: Int, height: Int
    let spans: [H4Span]
    let indices: [UInt8]
    /// One 8-bit alpha per index (255 for fully opaque layers).
    let alphas: [UInt8]
    let palette: [UInt8]

    init(_ layer: H4Layer) {
        width = max(layer.width, 0); height = max(layer.height, 0)
        spans = layer.spans
        indices = Array(layer.indices)
        alphas = (0..<indices.count).map { layer.alphaValue($0) }
        palette = layer.palette
    }

    /// Alpha (0…255) and RGB of the pixel at (x, y) of the layer, nil outside the spans.
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard y >= 0, y < spans.count else { return nil }
        let s = spans[y]
        guard x >= s.start, x < s.end else { return nil }
        let i = s.offset + x - s.start, c = Int(indices[i]) * 3
        return (palette[c], palette[c + 1], palette[c + 2], alphas[i])
    }
}

/// An adventure-map object model reduced to what drawing needs: footprint, header bytes, layer rectangles,
/// column depths, and the pixels of the layers that frame 1 uses (rule O3).
public final class H4ObjectModel: @unchecked Sendable {
    public struct LayerInfo: Sendable, Equatable {
        public var name: String
        public var left: Int, top: Int, right: Int, bottom: Int
        public var isEmpty: Bool
    }

    public let name: String
    /// Footprint: `width` runs along +row (x), `height` along +column (y).
    public let width: Int, height: Int
    public let imageKind: UInt8
    public let drawLayer: UInt8
    public let originX: Int, originY: Int
    public let layers: [LayerInfo]
    public let columnDepths: [Int16]
    /// O3: indices of the layers drawn in the static frame 1: bodies (`base_frame*` then `frame <nums>` listing 1) …
    public let bodyLayers: [Int]
    /// … and shadows (`base_shadow*` then `shadow <nums>` listing 1).
    public let shadowLayers: [Int]
    /// Left edge (relative to the anchor, origin included) of the leftmost non-empty `frame*`/`base_frame*` layer of
    /// any frame, or nil if the model has none.
    public let leftmostFrameEdge: Int?
    private let pixels: [Int: H4ObjectLayerPixels]

    public init(name: String, object o: H4AdventureObject) {
        self.name = name
        width = o.width; height = o.height
        imageKind = o.imageKind; drawLayer = o.drawLayer
        originX = Int(o.sprite.originX); originY = Int(o.sprite.originY)
        columnDepths = o.columnDepths
        let group = o.sprite.frames.layers
        layers = group.map { LayerInfo(name: $0.name, left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom, isEmpty: $0.isEmpty) }
        bodyLayers = Self.pick(layers, "frame")
        shadowLayers = Self.pick(layers, "shadow")
        let frames = layers.filter { !$0.isEmpty && ($0.name.hasPrefix("base_frame") || $0.name.hasPrefix("frame ")) }
        leftmostFrameEdge = frames.map(\.left).min().map { $0 + Int(o.sprite.originX) }
        var made: [Int: H4ObjectLayerPixels] = [:]
        for k in bodyLayers + shadowLayers { made[k] = H4ObjectLayerPixels(group[k]) }
        pixels = made
    }

    /// Numbers (digit runs) of a layer name such as "frame 001 002".
    static func numbers(in name: String) -> [Int] {
        var out: [Int] = [], current = ""
        for ch in name.unicodeScalars {
            if ch.value >= 48 && ch.value <= 57 { current.unicodeScalars.append(ch) }
            else if !current.isEmpty { if let n = Int(current) { out.append(n) }; current = "" }
        }
        if !current.isEmpty, let n = Int(current) { out.append(n) }
        return out
    }

    /// O3 for `kind` = "frame" or "shadow": non-empty `base_<kind>*` layers first, then non-empty `<kind> <nums>` listing 1.
    static func pick(_ layers: [LayerInfo], _ kind: String) -> [Int] {
        var base: [Int] = [], frame: [Int] = []
        for (k, l) in layers.enumerated() where !l.isEmpty {
            if l.name.hasPrefix("base_" + kind) { base.append(k) }
            else if l.name.hasPrefix(kind + " "), numbers(in: l.name).contains(1) { frame.append(k) }
        }
        return base + frame
    }

    /// Pixels of a layer selected by `bodyLayers` / `shadowLayers`.
    public func layerPixels(_ k: Int) -> H4ObjectLayerPixels? { pixels[k] }
}

/// Loads and caches object models by name. Models the archives do not have are recorded in `missingModels`.
public final class H4ObjectModelLibrary: @unchecked Sendable {
    private let loader: @Sendable (String) throws -> Data
    private let lock = NSLock()
    private var cache: [String: H4ObjectModel?] = [:]
    private var missing: Set<String> = []

    public init(loader: @escaping @Sendable (String) throws -> Data) { self.loader = loader }
    public convenience init(store: H4ResourceStore) { self.init(loader: { try store.data(for: $0) }) }

    public var missingModels: Set<String> { lock.lock(); defer { lock.unlock() }; return missing }

    /// The model named like the scenario record (`adv_object.<name>.h4d`), nil (and recorded) if there is none.
    public func model(named name: String) throws -> H4ObjectModel? {
        let key = name.lowercased()
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit { return hit }
        var made: H4ObjectModel?
        do {
            made = H4ObjectModel(name: name, object: try H4AdventureObject(data: loader("adv_object.\(name).h4d")))
        } catch H4Error.notFound {
            lock.lock(); missing.insert(name); lock.unlock()
        }
        lock.lock(); cache[key] = .some(made); lock.unlock()
        return made
    }
}

/// One entry of the object draw list.
public struct H4ObjectDrawItem: Sendable {
    public enum Kind: String, Sendable { case shadow, body }
    public var kind: Kind
    public var model: String
    /// Object position (row, column).
    public var x: Int, y: Int
    /// Index of the layer in the model's file order.
    public var layerIndex: Int
    /// 32-pixel screen column of a strip, nil for a whole layer.
    public var column: Int?

    /// Canvas position of the layer's top-left pixel.
    var left: Int, top: Int
    /// Screen x range the item may write to (strips), nil for the whole layer.
    var clip: Range<Int>?
    var pixels: H4ObjectLayerPixels
}

/// Objects of a region in drawing order (O4): all shadows in object-list order, then the body strips by sort key.
public struct H4ObjectDrawList: Sendable {
    public var items: [H4ObjectDrawItem] = []
    /// Number of scenario objects drawn (after O2).
    public var objectCount = 0

    /// The reference JSON shape: `[kind, model, x, y, layerIndex, column | null]` per item.
    public func json() throws -> Data {
        let rows: [[Any]] = items.map { [$0.kind.rawValue, $0.model, $0.x, $0.y, $0.layerIndex, $0.column.map { $0 as Any } ?? NSNull()] }
        return try JSONSerialization.data(withJSONObject: rows, options: [.withoutEscapingSlashes])
    }
}

/// Object rules of the adventure map (slice 6a-O), identical to the frozen reference `render_objects_ref.py`:
/// - O1 anchor of object (x = row, y = column) = top vertex of cell (x, y): A = (32((y−c0)−(x−r0)) + 32·nr, 16((x−r0)+(y−c0)));
///   a layer is drawn with its top-left at A + origin + rect.topLeft.
/// - O2 drawn: level equal, not an anonymous army, model known, and not (x+W < r0−2 or x > r0+nr+2 or y+H < c0−2 or y > c0+nc+2).
/// - O3 frame 1: bodies = `base_frame*` layers then `frame <nums>` listing 1; shadows likewise (file order, non-empty only).
/// - O4 shadow pass first (object-list order), then body strips sorted ascending (stable) by key:
///   ground objects (imageKind 1 or draw-layer byte 2): whole layer, key (−1, x+y, x);
///   others: one strip per body layer and 32-px column col in floor((left+ox)/32) … ceil((right+ox)/32)−1, depth columns aligned on
///   the union of all frame layers (first = floor(leftmost/32)), d = depths[col−first] or −1, key (0, x+y−d−1, x+y, x, col).
/// - O5 integer blends: shadow (dst·(510−a)+255)/510; body a=255 → src, else (dst·(255−a)+src·a+127)/255; written pixels become opaque;
///   an empty destination counts as black.
/// - O6 not drawn: owner flags, armies/heroes, animation frames beyond the first.
public enum H4MapObjectRender {
    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    static func ceilDiv(_ a: Int, _ b: Int) -> Int { -floorDiv(-a, b) }

    /// O1: canvas position of the anchor of the object at (row x, column y) for `region`.
    public static func anchor(x: Int, y: Int, region r: H4MapTerrainRender.Region) -> (x: Int, y: Int) {
        (32 * ((y - r.column) - (x - r.row)) + 32 * r.rows, 16 * ((x - r.row) + (y - r.column)))
    }

    /// O2.
    public static func isIncluded(x: Int, y: Int, width w: Int, height h: Int, region r: H4MapTerrainRender.Region) -> Bool {
        !(x + w < r.row - 2 || x > r.row + r.rows + 2 || y + h < r.column - 2 || y > r.column + r.columns + 2)
    }

    /// O4 key of a body strip: ground items and strips compare as the reference's Python tuples.
    struct SortKey: Comparable {
        var a: Int, b: Int, c: Int, d: Int, e: Int
        static func < (l: SortKey, r: SortKey) -> Bool {
            (l.a, l.b, l.c, l.d, l.e) < (r.a, r.b, r.c, r.d, r.e)
        }
    }

    /// Depth column key part for the strip of `col` (O4): `depths[col − first]` or −1.
    static func depth(of model: H4ObjectModel, column col: Int) -> Int {
        guard let edge = model.leftmostFrameEdge else { return -1 }
        let i = col - floorDiv(edge, 32)
        return model.columnDepths.indices.contains(i) ? Int(model.columnDepths[i]) : -1
    }

    public static func drawList(objects: [H4ScenarioObject], level: Int, region: H4MapTerrainRender.Region,
                                models: H4ObjectModelLibrary) throws -> H4ObjectDrawList {
        struct Placed { var x: Int, y: Int, model: H4ObjectModel, ax: Int, ay: Int }
        var placed: [Placed] = []
        for o in objects where Int(o.level) == level && o.classID != H4ScenarioObject.armyClassID {
            guard let m = try models.model(named: o.modelName) else { continue }
            let (x, y) = (Int(o.x), Int(o.y))
            guard isIncluded(x: x, y: y, width: m.width, height: m.height, region: region) else { continue }
            let a = anchor(x: x, y: y, region: region)
            placed.append(Placed(x: x, y: y, model: m, ax: a.x, ay: a.y))
        }
        var list = H4ObjectDrawList()
        list.objectCount = placed.count

        func item(_ kind: H4ObjectDrawItem.Kind, _ p: Placed, _ k: Int, column: Int?, clip: Range<Int>?) -> H4ObjectDrawItem {
            let l = p.model.layers[k]
            return H4ObjectDrawItem(kind: kind, model: p.model.name, x: p.x, y: p.y, layerIndex: k, column: column,
                                    left: p.ax + p.model.originX + l.left, top: p.ay + p.model.originY + l.top,
                                    clip: clip, pixels: p.model.layerPixels(k)!)
        }
        for p in placed {                                             // pass A
            for k in p.model.shadowLayers { list.items.append(item(.shadow, p, k, column: nil, clip: nil)) }
        }
        var strips: [(key: SortKey, order: Int, item: H4ObjectDrawItem)] = []
        for p in placed {                                             // pass B
            let m = p.model
            if m.bodyLayers.isEmpty { continue }
            if m.imageKind == 1 || m.drawLayer == 2 {
                for k in m.bodyLayers {
                    strips.append((SortKey(a: -1, b: p.x + p.y, c: p.x, d: 0, e: 0), strips.count, item(.body, p, k, column: nil, clip: nil)))
                }
                continue
            }
            for k in m.bodyLayers {
                let l = m.layers[k]
                for col in floorDiv(l.left + m.originX, 32)..<ceilDiv(l.right + m.originX, 32) {
                    let d = depth(of: m, column: col)
                    let key = SortKey(a: 0, b: p.x + p.y - d - 1, c: p.x + p.y, d: p.x, e: col)
                    strips.append((key, strips.count, item(.body, p, k, column: col, clip: (p.ax + 32 * col)..<(p.ax + 32 * col + 32))))
                }
            }
        }
        strips.sort { $0.key != $1.key ? $0.key < $1.key : $0.order < $1.order }
        list.items.append(contentsOf: strips.map(\.item))
        return list
    }

    // MARK: O5

    /// Blits `item` into `canvas` (RGBA, `width` wide, holding canvas rows y0 ..< y0 + rows).
    static func draw(_ item: H4ObjectDrawItem, canvas: UnsafeMutablePointer<UInt8>, width W: Int, y0: Int, rows: Int) {
        let L = item.pixels
        let shadow = item.kind == .shadow
        let lo = max(0, y0 - item.top), hi = min(L.height, y0 + rows - item.top)
        guard lo < hi else { return }
        var xmin = 0, xmax = W
        if let clip = item.clip { xmin = max(xmin, clip.lowerBound); xmax = min(xmax, clip.upperBound) }
        L.indices.withUnsafeBufferPointer { idx in
          L.alphas.withUnsafeBufferPointer { alphas in
            L.palette.withUnsafeBufferPointer { pal in
                for ly in lo..<hi {
                    let span = L.spans[ly]
                    let c0 = max(span.start, xmin - item.left), c1 = min(span.end, xmax - item.left)
                    guard c0 < c1 else { continue }
                    let row = canvas + ((item.top + ly - y0) * W + item.left) * 4
                    for c in c0..<c1 {
                        let i = span.offset + c - span.start
                        let a = Int(alphas[i])
                        guard a != 0 else { continue }
                        let d = row + c * 4, p = Int(idx[i]) * 3
                        if shadow {
                            d[0] = UInt8((Int(d[0]) * (510 - a) + 255) / 510)
                            d[1] = UInt8((Int(d[1]) * (510 - a) + 255) / 510)
                            d[2] = UInt8((Int(d[2]) * (510 - a) + 255) / 510)
                        } else if a == 255 {
                            d[0] = pal[p]; d[1] = pal[p + 1]; d[2] = pal[p + 2]
                        } else {
                            d[0] = UInt8((Int(d[0]) * (255 - a) + Int(pal[p]) * a + 127) / 255)
                            d[1] = UInt8((Int(d[1]) * (255 - a) + Int(pal[p + 1]) * a + 127) / 255)
                            d[2] = UInt8((Int(d[2]) * (255 - a) + Int(pal[p + 2]) * a + 127) / 255)
                        }
                        d[3] = 255
                    }
                }
            }
          }
        }
    }
}
