import Foundation

/// Shape of a scenario grid (from heroes4.exe 0x74dcf0 / 0x74e010, built with tile height 32).
///
/// A map of `size` rows is stored as an isometric diamond: row r holds the cells
/// `cellRows[r].start ..< cellRows[r].end`. Heights live on cell corners, in `size + 1` rows.
public struct H4MapGeometry: Sendable, Equatable {
    public let size: Int
    public let cellRows: [Range<Int>]
    public let vertexRows: [Range<Int>]

    public var cellCount: Int { cellRows.reduce(0) { $0 + $1.count } }
    public var vertexCount: Int { vertexRows.reduce(0) { $0 + $1.count } }

    public init(size n: Int, tileHeight h: Int = 32) {
        size = n
        // Integer arithmetic transcribed from the game (C division truncates toward zero).
        func div(_ a: Int, _ b: Int) -> Int { a / b }
        let w = n * h, hh = div(n * h, 2)
        var i11 = div(n * h - hh, 2)
        let i9 = div(2 * h * n - w, 2) - div(2 * h * n, 2)
        var i3 = div(i11 * 2, h)
        var i4 = div((h - 1) + (hh + i11) * 2, h)
        var i10 = div(2 * h - 1 + (w + i9) * 2, 2 * h) + 1
        i3 = (i3 - 1) - i4
        i11 = div(i9 * 2 - 2 * h + 1, 2 * h) - i10
        var rows: [Range<Int>] = []
        for _ in 0..<n {
            var start = i3 + i4
            if start < 0 { start = max(i11 + i10, 0) }
            let end = n < i10 ? (n < i4 ? n : i4) : i10
            rows.append(start..<max(end, start))
            i10 += 1; i4 -= 1
        }
        cellRows = rows
        var v: [Range<Int>] = [rows[0].lowerBound..<(rows[0].upperBound + 1)]
        for k in 1..<n {
            v.append(min(rows[k - 1].lowerBound, rows[k].lowerBound)..<(max(rows[k].upperBound, rows[k - 1].upperBound) + 1))
        }
        v.append(rows[n - 1].lowerBound..<(rows[n - 1].upperBound + 1))
        vertexRows = v
    }
}

/// One terrain cell (reader 0x413b30, record version 4 for scenario versions ≥ 26).
public struct H4TerrainCell: Sendable, Equatable {
    public struct Overlay: Sendable, Equatable { public let terrain: UInt8, variant: UInt8, value: UInt16, extra: UInt8 }
    public struct Road: Sendable, Equatable { public let kind: UInt8, value: UInt16, extra: UInt8 }

    /// 0 water, 1 grass, 2 rough, 3 swamp, 4 lava, 5 snow, 6 sand, 7 dirt, 8 subterranean;
    /// 9…18 are further types with a single variant.
    public let terrain: UInt8
    /// 0 or 1 → texture `<name>.1.x` or `<name>.2.x`.
    public let variant: UInt8
    public let a: UInt8, b: UInt8, c: Bool
    public let flags: UInt32
    public let overlays: [Overlay]
    public let roads: [Road]

    public static let terrainNames = ["water", "grass", "rough", "swamp", "lava", "snow", "sand", "dirt", "subterranean"]
    /// Variants allowed per terrain type (table at 0x9709d8).
    static let variantCounts: [UInt8] = [2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]

    static func recordVersion(scenarioVersion v: Int) -> Int {
        v > 25 ? 4 : v > 18 ? 3 : v > 7 ? 2 : v > 5 ? 1 : 0
    }

    /// Reads one cell; returns nil on any value the game would reject.
    static func read(_ d: UnsafeRawBufferPointer, _ o: inout Int, recordVersion rv: Int, limit: Int) -> H4TerrainCell? {
        func byte() -> UInt8? { guard o < limit else { return nil }; defer { o += 1 }; return d[o] }
        func u16() -> UInt16? { guard let lo = byte(), let hi = byte() else { return nil }; return UInt16(lo) | UInt16(hi) << 8 }
        func valid(_ t: UInt8, _ v: UInt8) -> Bool { t < 20 && variantCounts[Int(t)] > 0 && v < variantCounts[Int(t)] }
        guard let t = byte(), let v = byte(), valid(t, v), let a = byte(), a <= 3 else { return nil }
        var b: UInt8 = 0, c = false
        if rv >= 1 {
            // The game checks b ≤ 2 but only tests c for non-zero.
            guard let bb = byte(), bb <= 2, let cc = byte() else { return nil }
            b = bb; c = cc != 0
        }
        var flags: UInt32 = 0
        if rv >= 4 {
            guard let x0 = u16(), let x1 = u16() else { return nil }
            flags = UInt32(x0) | UInt32(x1) << 16
        } else if rv >= 3 {
            // Version 3 packs these 16 bits differently in game memory; kept raw here.
            guard let x = u16() else { return nil }
            flags = UInt32(x)
        }
        guard let n = byte() else { return nil }
        var overlays: [Overlay] = []
        for _ in 0..<n {
            guard let ot = byte(), let ov = byte(), valid(ot, ov), let val = u16(), let ex = byte() else { return nil }
            overlays.append(Overlay(terrain: ot, variant: ov, value: val, extra: ex))
        }
        guard let m = byte() else { return nil }
        var roads: [Road] = []
        for _ in 0..<m {
            guard let k = byte(), k < 4, let val = u16(), let ex = byte() else { return nil }
            roads.append(Road(kind: k, value: val, extra: ex))
        }
        return H4TerrainCell(terrain: t, variant: v, a: a, b: b, c: c, flags: flags, overlays: overlays, roads: roads)
    }
}

/// Terrain layers of a scenario, located without parsing the object section.
///
/// The game reads the terrain right after the objects (loader 0x4d12d0) and then the corner
/// heights, which end the file. Objects have no length prefix, so the terrain start is found
/// by trying candidate offsets: a candidate is accepted when every cell decodes with values the
/// game accepts and the cells end exactly where the height grid (whose size is known) begins.
/// On 73 of 85 shipped maps exactly one offset qualifies; see the tie-break below for the rest.
public struct H4ScenarioTerrain: Sendable {
    public let geometry: H4MapGeometry
    public let levels: Int
    /// `cells[level][row][column - geometry.cellRows[row].lowerBound]`.
    public let cells: [[[H4TerrainCell]]]
    /// One byte per corner, `heights[level][row][column - geometry.vertexRows[row].lowerBound]`.
    public let heights: [[[UInt8]]]
    /// Offset of the terrain in `H4Scenario.body`, and other offsets that also decode fully.
    public let start: Int
    public let alternativeStarts: [Int]
    /// Cells whose value depends on which of several fully-decoding offsets is chosen.
    public let uncertainCells: Int

    public init(scenario: H4Scenario) throws {
        guard scenario.size <= 320 else {
            throw H4Error.malformed("map size \(scenario.size) above the supported 320 (largest shipped map: 304)")
        }
        let geometry = H4MapGeometry(size: scenario.size)
        let levels = scenario.levels
        let rv = H4TerrainCell.recordVersion(scenarioVersion: scenario.version)
        let body = scenario.body
        let heightBytes = levels * geometry.vertexCount
        let end = body.count - heightBytes
        let cellCount = levels * geometry.cellCount
        let minimum = rv >= 4 ? 11 : 5
        guard end - cellCount * minimum >= 0 else { throw H4Error.malformed("scenario too short for its terrain") }

        // Linear search. Walking backwards from the end, remaining[o] is the number of cells that
        // decode back-to-back from offset o and land exactly on `end` (−1 when impossible); a start
        // is valid when that number equals the cell count. One cell is decoded per offset, so the
        // cost stays proportional to the window even for hostile files.
        let hi = end - cellCount * minimum
        let lo = max(0, end - cellCount * 40)    // real cells average ~13 bytes
        var candidates: [Int] = []
        body.withUnsafeBytes { raw in
            let d = UnsafeRawBufferPointer(rebasing: raw[0..<raw.count])
            var remaining = [Int32](repeating: -1, count: end - lo + 1)
            remaining[end - lo] = 0
            var o = end - 1
            while o >= lo {
                var next = o
                if H4TerrainCell.read(d, &next, recordVersion: rv, limit: end) != nil {
                    let r = remaining[next - lo]
                    if r >= 0 { remaining[o - lo] = r + 1 }
                }
                if o <= hi, remaining[o - lo] == Int32(cellCount) { candidates.append(o) }
                o -= 1
            }
        }
        guard !candidates.isEmpty else { throw H4Error.malformed("terrain block not found") }
        // A forged file could produce many aligned candidates; only a handful are ever compared.
        candidates = Array(candidates.prefix(8))

        func decode(from start: Int) -> [[[H4TerrainCell]]] {
            body.withUnsafeBytes { raw in
                let d = UnsafeRawBufferPointer(rebasing: raw[0..<raw.count])
                var o = start
                return (0..<levels).map { _ in
                    geometry.cellRows.map { range in
                        range.map { _ in H4TerrainCell.read(d, &o, recordVersion: rv, limit: end)! }
                    }
                }
            }
        }
        let found = candidates.map { ($0, decode(from: $0)) }

        // On 12 of the 85 shipped maps a second offset also decodes; the readings differ in up to
        // ~90 cells. Choose, in order: the reading with the fewest cells whose flags differ from
        // the dominant value (on unambiguous maps every cell has the same flags), then the best
        // terrain agreement of the differing cells with their unchanged neighbours, then the
        // later offset.
        var differing: Set<[Int]> = []
        if found.count > 1 {
            for l in 0..<levels {
                for (r, range) in geometry.cellRows.enumerated() {
                    for i in 0..<range.count where found.dropFirst().contains(where: { $0.1[l][r][i] != found[0].1[l][r][i] }) {
                        differing.insert([l, r, range.lowerBound + i])
                    }
                }
            }
        }
        var flagCounts: [UInt32: Int] = [:]
        for level in found[0].1 { for row in level { for cell in row { flagCounts[cell.flags, default: 0] += 1 } } }
        let dominantFlags = flagCounts.max { $0.value < $1.value }?.key ?? 0
        func oddFlags(_ grid: [[[H4TerrainCell]]]) -> Int {
            differing.reduce(0) { n, k in
                n + (grid[k[0]][k[1]][k[2] - geometry.cellRows[k[1]].lowerBound].flags == dominantFlags ? 0 : 1)
            }
        }
        func agreement(_ grid: [[[H4TerrainCell]]]) -> Int {
            var score = 0
            for key in differing {
                let (l, r, c) = (key[0], key[1], key[2])
                let t = grid[l][r][c - geometry.cellRows[r].lowerBound].terrain
                for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nr = r + dr, nc = c + dc
                    guard (0..<geometry.size).contains(nr), geometry.cellRows[nr].contains(nc),
                          !differing.contains([l, nr, nc]) else { continue }
                    if grid[l][nr][nc - geometry.cellRows[nr].lowerBound].terrain == t { score += 1 }
                }
            }
            return score
        }
        let ranked = found.map { (start: $0.0, grid: $0.1, odd: oddFlags($0.1), agree: agreement($0.1)) }
        let best = ranked.min { a, b in
            if a.odd != b.odd { return a.odd < b.odd }
            if a.agree != b.agree { return a.agree > b.agree }
            return a.start > b.start
        }!
        self.geometry = geometry
        self.levels = levels
        start = best.start
        cells = best.grid
        alternativeStarts = found.map(\.0).filter { $0 != best.start }
        uncertainCells = differing.count

        var hs: [[[UInt8]]] = []
        var o = body.startIndex + end
        for _ in 0..<levels {
            var rows: [[UInt8]] = []
            for range in geometry.vertexRows {
                rows.append([UInt8](body[o..<(o + range.count)]))
                o += range.count
            }
            hs.append(rows)
        }
        heights = hs
    }

    /// Terrain type at (level, row, column), or nil outside the diamond.
    public func cell(level: Int, row: Int, column: Int) -> H4TerrainCell? {
        guard (0..<levels).contains(level), (0..<geometry.size).contains(row),
              geometry.cellRows[row].contains(column) else { return nil }
        return cells[level][row][column - geometry.cellRows[row].lowerBound]
    }

    /// Screen-oriented minimap: the isometric diamond of the file becomes the rectangle seen in
    /// game. Cell (row r, column c) lands at x = c − r, y = c + r; cells on one screen row are two
    /// units apart, so each is drawn 2 pixels wide.
    public func minimap(level: Int, colour: (H4TerrainCell) -> (UInt8, UInt8, UInt8)) -> H4RGBAImage {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for (r, range) in geometry.cellRows.enumerated() where !range.isEmpty {
            minX = min(minX, range.lowerBound - r); maxX = max(maxX, range.upperBound - 1 - r)
            minY = min(minY, range.lowerBound + r); maxY = max(maxY, range.upperBound - 1 + r)
        }
        let width = maxX - minX + 2, height = maxY - minY + 1
        var img = H4RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
        for (r, range) in geometry.cellRows.enumerated() {
            for c in range {
                let (cr, cg, cb) = colour(cells[level][r][c - range.lowerBound])
                let x = c - r - minX, y = c + r - minY
                for dx in 0..<2 {
                    let p = (y * width + x + dx) * 4
                    (img.pixels[p], img.pixels[p + 1], img.pixels[p + 2], img.pixels[p + 3]) = (cr, cg, cb, 255)
                }
            }
        }
        return img
    }
}
