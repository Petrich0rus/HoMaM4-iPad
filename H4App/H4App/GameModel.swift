import CoreGraphics
import Foundation
import H4Kit
import os
import SwiftUI

/// The play session of a started game on one map: wraps `H4GameSession`, keeps the object draw lists the tiles use, and
/// turns every state change into the exact set of pixel rectangles to redraw (draw-list diff).
///
/// Everything runs on the main actor. Commands (`select`, `plan`, `move`, `endTurn`) change the session, rebuild the draw
/// list of the levels they touch, give it to the `MapSession` and invalidate the rectangles of the items that differ.
@MainActor
final class GameModel: ObservableObject {
    struct SelectedArmy: Equatable {
        let id: Int
        let label: String
        let cell: H4MoveCell
        let level: Int
        let points: Int
    }

    /// What the HUD shows.
    @Published private(set) var day = 1
    @Published private(set) var week = 1
    @Published private(set) var month = 1
    @Published private(set) var player = -1
    @Published private(set) var resources = [Int](repeating: 0, count: 7)
    @Published private(set) var selected: SelectedArmy?
    @Published private(set) var plan: H4PlannedPath?
    @Published private(set) var message: String?
    @Published private(set) var isWalking = false
    @Published var level = 0

    let map: MapSession
    let session: H4GameSession
    let game: H4Game
    let render: H4GameRender
    let seed: UInt32, difficulty: Int
    let hooks = MapGameHooks()
    let title: String
    let overlay: WalkOverlay
    let mapSize: Int

    /// Current draw list per level (the one the tiles use).
    private var lists: [H4ObjectDrawList]
    private let region: H4MapTerrainRender.Region
    private var messageTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "fr.petrichorus.H4App", category: "game")
    #if DEBUG
    /// Folder of the before/after draw-list dumps; nil = no dumps.
    var dumpDirectory: URL? = URL.documentsDirectory.appending(path: "debug", directoryHint: .isDirectory)
    private var sequence = 0
    #endif

    /// Everything `MapSession.loadGame` produced, to move between threads.
    struct Loaded: @unchecked Sendable {
        let map: MapSession
        let parts: MapSession.GameParts
    }

    init(loaded: Loaded, store: H4ResourceStore, seed: UInt32, difficulty: Int, mapSize: Int) {
        map = loaded.map
        session = loaded.parts.session
        game = loaded.parts.game
        render = loaded.parts.render
        self.seed = seed; self.difficulty = difficulty; self.mapSize = mapSize
        title = loaded.map.title
        region = .whole(size: mapSize)
        lists = loaded.map.levels.map(\.objects)
        overlay = WalkOverlay(store: store, mapSize: mapSize)
        hooks.onTap = { [weak self] level, row, column in self?.handleTap(level: level, row: row, column: column) }
        syncPublished()
        #if DEBUG
        try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: "debug", directoryHint: .isDirectory))
        #endif
    }

    // MARK: loading

    /// Loads the map and starts the game off the main thread.
    static func load(entry: MapEntry, store: H4ResourceStore, seed: UInt32, difficulty: Int,
                     progress: @escaping @Sendable (Double, String) -> Void) async -> Result<GameModel, Error> {
        let url = entry.url
        let size = entry.info?.size ?? 0
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Loaded, Error> in
            Result {
                let (map, parts) = try MapSession.loadGame(url: url, store: store, seed: seed, difficulty: difficulty, progress: progress)
                return Loaded(map: map, parts: parts)
            }
        }.value
        switch result {
        case .success(let loaded):
            return .success(GameModel(loaded: loaded, store: store, seed: seed, difficulty: difficulty, mapSize: size))
        case .failure(let error): return .failure(error)
        }
    }

    // MARK: HUD state

    static let playerNames = ["Red", "Blue", "Green", "Orange", "Purple", "Teal"]
    var playerName: String { Self.playerNames.indices.contains(player) ? Self.playerNames[player] : "-" }

    private func syncPublished() {
        day = session.day; week = session.week; month = session.month
        player = session.currentPlayer
        resources = session.resources(player: session.currentPlayer)?.amounts ?? [Int](repeating: 0, count: 7)
        if let id = session.selectedArmy, let a = session.army(id) {
            selected = SelectedArmy(id: id, label: actorLabel(army: a), cell: a.cell, level: a.level, points: a.pointsLeft)
        } else {
            selected = nil
        }
        plan = session.currentPlan
    }

    /// Name of the sprite of an army, from the draw list ("adv_actor.<name>" at its cell).
    private func actorName(army a: H4SessionArmy) -> String? {
        for item in lists[a.level].items where item.kind == .body && item.x == a.cell.r && item.y == a.cell.c && item.model.hasPrefix("adv_actor.") {
            return String(item.model.dropFirst("adv_actor.".count))
        }
        return nil
    }

    private func actorLabel(army a: H4SessionArmy) -> String {
        guard let name = actorName(army: a) else { return "Army \(a.id)" }
        return name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " · ")
    }

    func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    private static func explain(_ why: H4SessionWhy) -> String {
        switch why {
        case .goalArmy: return "An army is in the way (combat is not available yet)."
        case .goalBlocked: return "That cell cannot be entered."
        case .noPath: return "No path to that cell."
        case .goalOutOfMap: return "Outside the map."
        case .startInvalid: return "The army cannot start from its cell."
        case .notOwn: return "That army is not yours."
        case .noSelection: return "Select one of your armies first."
        case .noPlan: return "Choose a destination first."
        case .noSteps: return "Nothing to walk."
        case .noPoints: return "No movement points left today."
        }
    }

    // MARK: draw lists and invalidation

    /// State for the renderer: the session's plus the selection ring (and the hidden army while it walks).
    private func drawState(hiding army: Int? = nil) -> H4SessionRenderState {
        var s = session.renderState
        if let army {
            s.removed.insert(army)
        } else if let id = session.selectedArmy, let a = session.army(id) {
            if s.arrows.isEmpty { s.arrowLevel = a.level }
            s.arrows.append((cell: a.cell, model: "internal.selected.army"))
        }
        return s
    }

    private func buildList(level: Int, state: H4SessionRenderState) -> H4ObjectDrawList {
        do {
            return try render.drawList(objects: session.scenarioObjects, game: game, level: level, region: region, state: state)
        } catch {
            log("GAME error draw-list level=\(level) \(error)")
            return lists[level]
        }
    }

    private func levelsTouched(_ ids: [Int?]) -> [Int] {
        var out: Set<Int> = []
        for id in ids { if let id, let a = session.army(id) { out.insert(a.level) } }
        return out.sorted()
    }

    private func log(_ line: String) {
        print(line)
        logger.log("\(line, privacy: .public)")
    }

    // Draw items that differ between two lists (multiset difference on the public key; two items with the same key have the
    // same pixel box).
    private struct ItemKey: Hashable {
        let kind: String, model: String
        let x: Int, y: Int, layer: Int, column: Int
        init(_ i: H4ObjectDrawItem) {
            kind = i.kind.rawValue; model = i.model; x = i.x; y = i.y; layer = i.layerIndex; column = i.column ?? Int.min
        }
    }

    static func difference(_ old: H4ObjectDrawList, _ new: H4ObjectDrawList) -> (removed: [H4ObjectDrawItem], added: [H4ObjectDrawItem]) {
        var pool: [ItemKey: [Int]] = [:]
        for (i, item) in old.items.enumerated() { pool[ItemKey(item), default: []].append(i) }
        var added: [H4ObjectDrawItem] = []
        for item in new.items {
            let key = ItemKey(item)
            if var idx = pool[key], !idx.isEmpty { idx.removeLast(); pool[key] = idx } else { added.append(item) }
        }
        var removed: [H4ObjectDrawItem] = []
        for (_, idx) in pool { for i in idx { removed.append(old.items[i]) } }
        return (removed, added)
    }

    /// Pixel box of a draw item on the scale-1 canvas: the layer rectangle, cut to the strip's columns. `H4ObjectDrawItem`
    /// keeps its position and pixels internal, so they are read by reflection (H4Kit stays unchanged).
    static func box(_ item: H4ObjectDrawItem) -> CGRect {
        var left = 0, top = 0
        var clip: Range<Int>?
        var width = 0, height = 0
        for child in Mirror(reflecting: item).children {
            switch child.label {
            case "left": left = child.value as? Int ?? 0
            case "top": top = child.value as? Int ?? 0
            case "clip": clip = child.value as? Range<Int>
            case "pixels":
                if let p = child.value as? H4ObjectLayerPixels { width = p.width; height = p.height }
            default: break
            }
        }
        var x0 = left, x1 = left + width
        if let clip { x0 = max(x0, clip.lowerBound); x1 = min(x1, clip.upperBound) }
        return CGRect(x: x0, y: top, width: max(0, x1 - x0), height: height)
    }

    /// Rectangles to redraw for a change from `old` to `new`: the boxes of the items in only one of them, without empty
    /// ones, duplicates or rectangles inside another one (the union is exactly that of the boxes).
    static func invalidationRects(_ old: H4ObjectDrawList, _ new: H4ObjectDrawList) -> [CGRect] {
        let (removed, added) = difference(old, new)
        var boxes: [CGRect] = []
        var seen: Set<String> = []
        for item in removed + added {
            let b = box(item)
            guard b.width > 0, b.height > 0, seen.insert("\(b.minX),\(b.minY),\(b.width),\(b.height)").inserted else { continue }
            boxes.append(b)
        }
        return reduce(boxes)
    }

    static func reduce(_ boxes: [CGRect]) -> [CGRect] {
        let sorted = boxes.sorted { ($0.width * $0.height, $0.minX, $0.minY) > ($1.width * $1.height, $1.minX, $1.minY) }
        var kept: [CGRect] = []
        for b in sorted where !kept.contains(where: { $0.contains(b) }) { kept.append(b) }
        return kept.sorted { ($0.minY, $0.minX, $0.width, $0.height) < ($1.minY, $1.minX, $1.width, $1.height) }
    }

    private func logInvalidation(_ op: String, _ rects: [CGRect]) {
        let text = rects.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" }.joined(separator: " ")
        log("INVAL \(op) \(rects.count) rects \(text)")
    }

    #if DEBUG
    /// `[kind, model, x, y, layer, column, left, top, width, height]` per item (boxes cut to the strip), canonical JSON.
    private func dumpText(_ list: H4ObjectDrawList) -> String {
        var out = "["
        for (n, item) in list.items.enumerated() {
            let b = Self.box(item)
            if n > 0 { out += "," }
            out += "[\"\(item.kind.rawValue)\",\(Self.jsonString(item.model)),\(item.x),\(item.y),\(item.layerIndex),"
            out += "\(item.column.map(String.init) ?? "null"),\(Int(b.minX)),\(Int(b.minY)),\(Int(b.width)),\(Int(b.height))]"
        }
        return out + "]"
    }

    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case let c where c.value < 0x20 || c.value > 0x7e: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }

    private func dump(op: String, level: Int, before: H4ObjectDrawList, after: H4ObjectDrawList) {
        guard let dir = dumpDirectory else { return }
        sequence += 1
        let base = String(format: "%04d_%@", sequence, op)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? dumpText(before).write(to: dir.appending(path: base + "_before.json"), atomically: true, encoding: .utf8)
        try? dumpText(after).write(to: dir.appending(path: base + "_after.json"), atomically: true, encoding: .utf8)
        log("DUMP \(op) seq=\(sequence) level=\(level) files=\(base)_{before,after}.json")
    }
    #endif

    /// Replaces the draw list of `level` and redraws the given rectangles.
    private func install(_ list: H4ObjectDrawList, level: Int, invalidating rects: [CGRect]) {
        lists[level] = list
        map.setObjects(list, level: level)
        hooks.invalidate(canvasRects: rects)
    }

    /// Rebuilds the lists of `levels` for the current session state, logs, dumps and invalidates. Returns the rectangles.
    @discardableResult
    private func refresh(op: String, levels: [Int]) -> [CGRect] {
        var all: [CGRect] = []
        for l in levels {
            let old = lists[l]
            let new = buildList(level: l, state: drawState())
            let rects = Self.invalidationRects(old, new)
            #if DEBUG
            dump(op: op, level: l, before: old, after: new)
            #endif
            logInvalidation(op, rects)
            install(new, level: l, invalidating: rects)
            all += rects
        }
        return all
    }

    // MARK: commands

    private func resourceText() -> String { resources.map(String.init).joined(separator: "/") }

    private func logState(_ op: String, _ extra: String) {
        var own: [String] = []
        for a in session.armies where a.owner == session.currentPlayer && own.count < 6 {
            own.append("\(a.id)@\(a.cell.r),\(a.cell.c):\(a.pointsLeft)")
        }
        var line = "GAME \(op) \(extra) player=\(session.currentPlayer) day=\(session.day) week=\(session.week) month=\(session.month)"
        line += " res(gold/wood/ore/crystal/sulfur/mercury/gem)=" + (session.resources(player: session.currentPlayer)?.amounts.map(String.init).joined(separator: "/") ?? "-")
        if let id = session.selectedArmy, let a = session.army(id) {
            line += " army=\(id) cell=\(a.cell.r),\(a.cell.c) level=\(a.level) points=\(a.pointsLeft)"
            let bag = session.backpack(army: id)
            if !bag.isEmpty { line += " backpack=\(bag.map(String.init).joined(separator: ","))" }
        }
        if op == "endturn" { line += " own=" + own.joined(separator: ",") }
        log(line)
    }

    @discardableResult
    func select(army id: Int) -> Result<Void, H4SessionWhy> {
        guard !isWalking else { return .failure(.noPoints) }
        let previous = session.selectedArmy
        let result = session.select(army: id)
        syncPublishedAfterOp()
        switch result {
        case .success:
            logState("select", "ok=true")
            refresh(op: "select", levels: levelsTouched([previous, id]))
        case .failure(let why):
            logState("select", "ok=false why=\(why.rawValue) target=\(id)")
            show(Self.explain(why))
        }
        syncPublished()
        return result
    }

    private func syncPublishedAfterOp() { syncPublished() }

    @discardableResult
    func plan(to cell: H4MoveCell) -> H4PlannedPath {
        let sel = session.selectedArmy
        let p = session.plan(to: cell)
        syncPublished()
        if p.ok {
            logState("plan", "ok=true to=\(cell.r),\(cell.c) cost=\(p.cost) days=\(p.days) steps=\(p.path.count - 1)")
        } else {
            logState("plan", "ok=false why=\(p.why?.rawValue ?? "-") to=\(cell.r),\(cell.c)")
            if let why = p.why { show(Self.explain(why)) }
        }
        refresh(op: "plan", levels: levelsTouched([sel]))
        return p
    }

    @discardableResult
    func move(animated: Bool = true) -> H4MoveOutcome {
        guard let id = session.selectedArmy, let start = session.army(id), let planned = session.currentPlan, !isWalking else {
            let out = session.move()
            logState("move", "ok=\(out.ok) why=\(out.why?.rawValue ?? "-")")
            if let why = out.why { show(Self.explain(why)) }
            return out
        }
        let level = start.level
        let before = lists[level]
        let resourcesBefore = resources, bagBefore = session.backpack(army: id).count
        let pointsBefore = start.pointsLeft
        let out = session.move()
        syncPublished()
        guard out.ok else {
            logState("move", "ok=false why=\(out.why?.rawValue ?? "-")")
            if let why = out.why { show(Self.explain(why)) }
            return out
        }
        logState("move", "ok=true steps=\(out.steps) spent=\(out.spent) picked=\(out.picked.map(String.init) ?? "-") from=\(start.cell.r),\(start.cell.c) pointsBefore=\(pointsBefore)")
        if out.picked != nil {
            let bag = session.backpack(army: id)
            if bag.count > bagBefore { show("Picked up artifact \(bag.last!).") }
            else { show("Picked up " + Self.gained(from: resourcesBefore, to: resources) + ".") }
        }
        let end = session.army(id)!.cell
        let walked = Array(planned.path.prefix(through: planned.path.firstIndex(of: end) ?? 0))
        let final = buildList(level: level, state: drawState())

        // Animated walk: the tiles show the world after the move but without the walking army (and its ring); the overlay
        // sprite walks; at the end the tiles get the army and ring at the destination. Both steps together redraw exactly
        // what a direct change from `before` to `final` would.
        let hidden = buildList(level: level, state: drawState(hiding: id))
        let rectsStart = Self.invalidationRects(before, hidden), rectsEnd = Self.invalidationRects(hidden, final)
        #if DEBUG
        dump(op: "move", level: level, before: before, after: final)
        #endif
        logInvalidation("move", Self.reduce(rectsStart + rectsEnd))

        if animated, walked.count >= 2, hooks.isAttached, let host = hooks.host, let actor = actorName(army: start) {
            install(hidden, level: level, invalidating: rectsStart)
            isWalking = true
            let started = overlay.run(actor: actor, owner: start.owner, cells: walked, host: host) { [weak self] in
                guard let self else { return }
                self.install(final, level: level, invalidating: rectsEnd)
                self.overlay.hide(after: 0.15)
                self.isWalking = false
                self.syncPublished()
            }
            if started { return out }
            isWalking = false
        }
        install(final, level: level, invalidating: Self.reduce(rectsStart + rectsEnd))
        return out
    }

    private static func gained(from old: [Int], to new: [Int]) -> String {
        let parts = zip(old, new).enumerated().compactMap { i, p in p.1 > p.0 ? "+\(p.1 - p.0) \(H4SessionResources.names[i])" : nil }
        return parts.isEmpty ? "an object" : parts.joined(separator: ", ")
    }

    func endTurn() {
        guard !isWalking else { return }
        let previous = session.selectedArmy
        session.endTurn()
        syncPublished()
        logState("endturn", "ok=true")
        refresh(op: "endturn", levels: levelsTouched([previous]))
        show("\(playerName) — day \(day), week \(week), month \(month)")
    }

    // MARK: touch

    func handleTap(level: Int, row: Int, column: Int) {
        guard !isWalking else { return }
        let cell = H4MoveCell(row, column)
        if let own = session.armies.first(where: { $0.level == level && $0.cell == cell && $0.owner == session.currentPlayer }) {
            select(army: own.id)
            return
        }
        guard let id = session.selectedArmy, let army = session.army(id) else {
            show("Tap one of your armies first.")
            return
        }
        guard army.level == level else {
            show("The selected army is on the other level.")
            return
        }
        if let p = session.currentPlan, p.ok, p.path.last == cell {
            move()
        } else {
            plan(to: cell)
        }
    }
}
