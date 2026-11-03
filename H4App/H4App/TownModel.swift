import CoreGraphics
import Foundation
import H4Kit
import SwiftUI

/// State of the town screen. It never decides a rule: the numbers and refusals come from the `H4GameSession` queries
/// (`buildStatus`, `recruitPreview`, `transferPreview`) and every change goes through `GameModel.execute` (the q4 entry).
@MainActor
final class TownModel: ObservableObject {
    enum Sheet: Equatable {
        case build
        case recruit(Int)
    }

    /// A stack picked as the source of a transfer: `army` nil = the garrison of the open town.
    struct Picked: Equatable {
        var army: Int?
        var slot: Int
        var half: Bool
    }

    @Published private(set) var current: Int?
    @Published private(set) var image: CGImage?
    @Published private(set) var sceneError: String?
    /// Bumped after every command so that views re-read the session.
    @Published private(set) var revision = 0
    @Published var sheet: Sheet?
    @Published var picked: Picked?
    @Published var recruitCount = 0
    @Published private(set) var notice: String?

    weak var game: GameModel?
    /// Number of items of the last scene draw list (AutoTown checks it is not empty).
    private(set) var drawCount = 0
    private let renderer: H4TownRenderer          // used by the render task only
    private let thumbRenderer: H4TownRenderer     // used on the main actor only (thumbnails)
    private var plan: H4TownScene?
    private var renderTask: Task<Void, Never>?
    private var renderToken = 0
    private var noticeTask: Task<Void, Never>?
    private var thumbs: [String: CGImage] = [:]

    init(store: H4ResourceStore) {
        renderer = H4TownRenderer(store: store)
        thumbRenderer = H4TownRenderer(store: store)
    }

    // MARK: screen

    var session: H4GameSession? { game?.session }
    var town: H4TownState? { current.flatMap { session?.town($0) } }

    /// Opens the screen of an own town of the current player; false (nothing changes) for any other town.
    @discardableResult
    func open(_ index: Int) -> Bool {
        guard let session, let t = session.town(index), t.owner == session.currentPlayer else { return false }
        if current == index { return true }
        current = index
        sheet = nil; picked = nil; notice = nil
        image = nil; sceneError = nil; plan = nil; drawCount = 0
        renderScene()
        return true
    }

    func close() {
        guard current != nil else { return }
        current = nil
        sheet = nil; picked = nil; notice = nil
        renderToken += 1
        image = nil; plan = nil
    }

    /// Waits for the scene render in flight.
    func settle() async { await renderTask?.value }

    private func renderScene() {
        guard let session, let index = current, let t = session.town(index) else { return }
        renderToken += 1
        let token = renderToken
        let terrain = session.townTerrain(town: index)
        let faction = t.faction
        let built = H4TownRender.maskIDs(t.mask)
        let renderer = self.renderer
        let previous = renderTask
        renderTask = Task { [weak self] in
            await previous?.value                                   // the renderer is not thread safe: one render at a time
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(H4TownScene, CGImage, Int), Error> in
                Result {
                    guard let background = H4TownRender.backgroundName(terrain: terrain) else {
                        throw H4Error.malformed("no background for terrain id \(terrain)")
                    }
                    let scene = try renderer.plan(faction: faction, background: background, built: built)
                    let (pixels, list) = try scene.render()
                    guard !list.isEmpty, let cg = pixels.cgImage() else { throw H4Error.malformed("empty town scene") }
                    return (scene, cg, list.count)
                }
            }.value
            guard let self, self.renderToken == token else { return }
            switch result {
            case .success(let (scene, cg, count)):
                self.plan = scene; self.image = cg; self.drawCount = count; self.sceneError = nil
            case .failure(let error):
                self.sceneError = "\(error)"; self.drawCount = 0
            }
        }
    }

    // MARK: touch

    /// A tap on the scene at scene pixel (x, y): a dwelling opens the recruit sheet, anything else the build sheet.
    func tapScene(x: Int, y: Int) {
        guard sheet == nil, let session, let index = current else { return }
        if let plan, let hit = try? plan.hitTest(points: [(x, y)]).first, let id = hit.id, (12...19).contains(id),
           session.recruitPreview(town: index, building: id) != nil {
            openRecruit(id)
        } else {
            sheet = .build
        }
    }

    func openRecruit(_ building: Int) {
        guard let session, let index = current, let p = session.recruitPreview(town: index, building: building) else { return }
        recruitCount = p.maxAffordable
        sheet = .recruit(building)
    }

    func thumbnail(faction: Int, building: Int) -> CGImage? {
        let key = "\(faction).\(building)"
        if let c = thumbs[key] { return c }
        guard let t = try? thumbRenderer.thumbnail(faction: faction, building: building), let layer = t.layer, !layer.isEmpty,
              let cg = layer.rgba().cgImage() else { return nil }
        thumbs[key] = cg
        return cg
    }

    // MARK: commands (all through `perform`)

    /// The town a town command is about: `town` for build / recruit, the `town` container of `from` (else of `to`) for a transfer.
    static func townIndex(of command: [String: Any]) -> Int? {
        func int(_ v: Any?) -> Int? { (v as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue } }
        switch command["op"] as? String {
        case "build", "recruit": return int(command["town"])
        case "transfer":
            if let t = int((command["from"] as? [String: Any])?["town"]) { return t }
            return int((command["to"] as? [String: Any])?["town"])
        default: return nil
        }
    }

    /// Runs a town command (from a finger or from a script): opens the screen of its town when it is an own town of the
    /// current player, executes it, and refreshes HUD, map model and scene from the result.
    @discardableResult
    func perform(_ command: [String: Any]) throws -> H4LogRecord {
        guard let game else { throw H4Error.malformed("no game") }
        let op = command["op"] as? String ?? ""
        let target = Self.townIndex(of: command)
        if let target { open(target) }
        let record = try game.execute(command)
        game.afterTownCommand(op: op, record: record, town: target)
        if op == "build", record.ok, target == current { renderScene() }
        revision += 1
        return record
    }

    func flash(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    func build(_ building: Int) {
        guard let index = current, let record = try? perform(["op": "build", "town": index, "building": building]) else { return }
        if record.ok {
            sheet = nil
            flash("Built: \(session?.buildingName(faction: town?.faction ?? 0, building: building) ?? "")")
        } else {
            flash(H4TownLabels.build(record.why))
        }
    }

    func recruit(building: Int, count: Int) {
        guard let index = current, count >= 1,
              let record = try? perform(["op": "recruit", "town": index, "building": building, "count": count]) else { return }
        if record.ok {
            sheet = nil
            let n = record.int("recruited") ?? count
            let creature = H4TownRules.dwellingCreature(faction: town?.faction ?? 0, building: building)
            flash("Recruited \(n) \(creature.flatMap { session?.creatureName($0, plural: n != 1) } ?? "creatures")")
        } else {
            flash(H4TownLabels.troops(record.why))
        }
    }

    private func container(_ army: Int?, _ slot: Int) -> [String: Any] {
        if let army { return ["army": army, "slot": slot] }
        return ["town": current ?? -1, "slot": slot]
    }

    func stack(army: Int?, slot: Int) -> H4SlotStack? {
        let row = army.map { session?.slots(army: $0) } ?? town?.garrison
        guard let row, row.indices.contains(slot) else { return nil }
        return row[slot]
    }

    /// A tap on a slot: the first tap picks a stack, the second one moves it (the whole stack, or half after a long press).
    func tapSlot(army: Int?, slot: Int) {
        guard sheet == nil else { return }
        guard let from = picked else {
            guard let s = stack(army: army, slot: slot), s.creature != -1 else { return }
            picked = Picked(army: army, slot: slot, half: false)
            return
        }
        if from.army == army && from.slot == slot { picked = nil; return }
        var command: [String: Any] = ["op": "transfer", "from": container(from.army, from.slot), "to": container(army, slot)]
        if from.half, let n = stack(army: from.army, slot: from.slot)?.count { command["count"] = n / 2 }
        picked = nil
        guard let record = try? perform(command) else { return }
        if !record.ok { flash(H4TownLabels.troops(record.why)) }
    }

    /// A long press on a stack of two or more picks half of it.
    func longPressSlot(army: Int?, slot: Int) {
        guard sheet == nil, picked == nil, let s = stack(army: army, slot: slot), s.creature >= 0 else { return }
        if s.count < 2 { flash("A single creature cannot be split"); return }
        picked = Picked(army: army, slot: slot, half: true)
    }
}
