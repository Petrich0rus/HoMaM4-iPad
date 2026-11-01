import Foundation
import Testing
@testable import H4Kit

// Slice 7d-L: turn logic. Synthetic sessions (flat grass levels, hand-made footprints) exercise calendar, points, pickups,
// world mutation, nearest-pickup ordering and the arrow rule; data-gated tests replay the frozen oracle scripts.
//   H4_DATA_DIR, H4_MAPS_DIR           game folders
//   H4_SESSION_ORACLE_DIR              folder with scripts/s1..s5.json, logs/s1..s5.json and arrows10.json
//   H4_RENDER7C_REF_DIR (optional)     not used here

private let env = ProcessInfo.processInfo.environment
private let hasData = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil
private let hasOracle = hasData && env["H4_SESSION_ORACLE_DIR"] != nil

// MARK: - Synthetic sessions

private typealias Obj = H4GameSession.Object

private func cell(_ r: Int, _ c: Int) -> H4MoveCell { H4MoveCell(r, c) }
private func why(_ r: Result<Void, H4SessionWhy>) -> H4SessionWhy? { if case .failure(let w) = r { return w }; return nil }

private func armyObj(_ x: Int, _ y: Int, owner: Int = 0) -> Obj {
    Obj(className: "army", modelName: "", subclass: "", x: x, y: y, level: 0, resolved: nil, footprint: nil, armyOwner: owner)
}

/// A pickup/blocking object. Default: 1x1 with all four entrance edges.
private func obj(_ cls: String, _ x: Int, _ y: Int, model: String = "", sub: String = "", resolved: H4ResolvedObject? = nil,
                 w: Int = 1, h: Int = 1, blocked: [Bool]? = nil, eh: [Bool]? = nil, ev: [Bool]? = nil) -> Obj {
    let fp = H4MoveFootprint(width: w, height: h, blocked: blocked ?? [Bool](repeating: true, count: w * h),
                             edgesHorizontal: eh ?? [Bool](repeating: true, count: (h + 1) * w),
                             edgesVertical: ev ?? [Bool](repeating: true, count: (w + 1) * h))
    return Obj(className: cls, modelName: model, subclass: sub, x: x, y: y, level: 0, resolved: resolved, footprint: fp, armyOwner: nil)
}

private func session(_ objects: [Obj], players: [(Int, Bool)] = [(0, true)], size: Int = 30, water: Set<H4MoveCell> = [],
                     artifacts: [String: Int] = [:]) -> H4GameSession {
    H4GameSession(players: players.map { (colour: $0.0, human: $0.1) }, objects: objects, levels: 1, artifactIDByModel: artifacts,
                  world: { _, placed in
                      H4MoveWorld(size: size, rows: Array(repeating: 0..<size, count: size),
                                  cell: { r, c in (water.contains(cell(r, c)) ? 0 : 1, 0, 0) }, placed: placed)
                  })
}

// MARK: - Calendar (rule 2)

@Test func calendarRollover() {
    let s = session([armyObj(0, 0)])
    #expect((s.day, s.week, s.month) == (1, 1, 1) && s.currentPlayer == 0)
    for _ in 0..<6 { s.endTurn() }
    #expect((s.day, s.week, s.month) == (7, 1, 1))
    s.endTurn()
    #expect((s.day, s.week, s.month) == (1, 2, 1))
    for _ in 0..<(7 * 3) { s.endTurn() }
    #expect((s.day, s.week, s.month) == (1, 1, 2))                       // 4 weeks per month
    for _ in 0..<(28 * 12) { s.endTurn() }
    #expect((s.day, s.week, s.month) == (1, 1, 14))
}

@Test func hotSeatOrderAndNeutralPlayers() {
    // players 1 (human), 2 (AI), 4 (human): hot seat 1 -> 4; the day advances after the last human only
    let s = session([armyObj(0, 0, owner: 1), armyObj(3, 3, owner: 4), armyObj(6, 6, owner: 6)], players: [(4, true), (2, false), (1, true)])
    #expect(s.currentPlayer == 1 && s.players == [1, 2, 4])
    #expect(why(s.select(army: 1)) == .notOwn && why(s.select(army: 2)) == .notOwn && why(s.select(army: 9)) == .notOwn)
    #expect(why(s.select(army: 0)) == nil)
    s.plan(to: cell(0, 4))
    #expect(s.move().ok)
    let spent = 2256 - s.army(0)!.pointsLeft
    #expect(spent == 400)
    s.endTurn()
    #expect(s.currentPlayer == 4 && s.day == 1 && s.selectedArmy == nil && s.currentPlan == nil)
    #expect(s.army(0)!.pointsLeft == 2256 - spent)                       // no reset between humans
    #expect(why(s.select(army: 0)) == .notOwn && why(s.select(army: 1)) == nil)
    s.endTurn()
    #expect(s.currentPlayer == 1 && s.day == 2 && s.army(0)!.pointsLeft == 2256)
    // no human: nobody is selectable, the day still advances
    let n = session([armyObj(0, 0, owner: 0)], players: [(0, false)])
    #expect(n.currentPlayer == -1 && why(n.select(army: 0)) == .notOwn)
    n.endTurn()
    #expect(n.day == 2 && n.currentPlayer == -1)
}

// MARK: - Points (rule 3)

@Test func pointsAreChargedPerStepAndDayOneStepsAreNotTaken() {
    let s = session([armyObj(0, 0)])
    #expect(s.move() == H4MoveOutcome(ok: false, why: .noSelection, steps: 0, picked: nil, spent: 0))
    _ = s.select(army: 0)
    #expect(s.plan(to: cell(0, 1)).ok)
    #expect(s.move().why == nil && s.army(0)!.cell == cell(0, 1) && s.army(0)!.pointsLeft == 2156)
    #expect(s.move().why == .noPlan)
    #expect(s.plan(to: cell(0, 1)).ok && s.move().why == .noSteps)       // start == goal: no step
    // from (0,1) with 2156 points: 21 steps leave 56, the 22nd (100 >= 56) exhausts the day and is still taken
    let p = s.plan(to: cell(0, 25))
    #expect(p.ok && p.cost == 2400 && p.days == 2)
    #expect(p.dayOf.filter { $0 == 0 }.count == 22 && p.dayOf.last == 1)
    let m = s.move()
    #expect(m.ok && m.steps == 22 && m.spent == 2200 && m.picked == nil)
    #expect(s.army(0)!.cell == cell(0, 23) && s.army(0)!.pointsLeft == 0)  // overflow of the exhausting step is lost
    // 0 points left: the first step is on day 1 -> refused, the plan is kept
    let q = s.plan(to: cell(0, 25))
    #expect(q.ok && q.dayOf == [1, 1] && q.days == 2)
    #expect(s.move() == H4MoveOutcome(ok: false, why: .noPoints, steps: 0, picked: nil, spent: 0) && s.currentPlan != nil)
    s.endTurn()
    #expect(s.army(0)!.pointsLeft == 2256 && s.currentPlan == nil)
    // a failed plan clears the stored plan and reports the movement reason
    _ = s.select(army: 0)
    #expect(s.plan(to: cell(0, 24)).ok)
    #expect(s.plan(to: cell(99, 0)).why == .goalOutOfMap && s.currentPlan == nil && s.move().why == .noPlan)
}

// MARK: - Pickup effects (rule 5), world mutation (rule 4)

@Test func pickupEffectsOfEveryClass() {
    func res(_ build: (inout H4ResolvedObject) -> Void) -> H4ResolvedObject { var r = H4ResolvedObject(); build(&r); return r }
    let objs = [
        armyObj(5, 0),
        obj("treasure", 5, 3, model: "Resources.Treasure Chest", sub: "treasure_chest"),
        obj("campfire", 5, 6, model: "Resources.Campfire"),
        obj("material_pile", 5, 9, model: "Resources.Gold", sub: "gold_pile"),
        obj("material_pile", 5, 12, model: "Resources.Mercury", sub: "pot_of_mecury"),
        obj("material_pile", 5, 15, model: "Resources.Wood", sub: "wood_pile"),
        obj("random_material_pile", 5, 18, resolved: res { $0.model = "Resources.Sulfur"; $0.material = 4; $0.amount = 7 }),
        obj("random_artifact", 5, 21, resolved: res { $0.model = "artifacts.x"; $0.artifact = 77 }),
        obj("random_tome", 5, 24, resolved: res { $0.model = "artifacts.t"; $0.artifact = 200 }),
        obj("artifact", 8, 24, model: "artifacts.Boots.Boots of Travel"),
        obj("artifact", 11, 24, model: "artifacts.nothing.Unknown"),
        obj("mine", 14, 24, model: "Mines.Ore"),                     // not a pickup class
    ]
    let s = session(objs, artifacts: ["artifacts.boots.boots of travel": 55])
    func take(_ idx: Int) -> H4MoveOutcome {
        _ = s.select(army: 0)
        let o = objs[idx]
        let p = s.plan(to: cell(o.x, o.y))
        #expect(p.ok, "plan to object \(idx)")
        let m = s.move()
        #expect(m.ok && m.picked == idx, "pickup of object \(idx)")
        s.endTurn()
        return m
    }
    for i in 1...10 { _ = take(i) }
    let r = s.resources(player: 0)!
    #expect(r.gold == 1000 + 500 + 600 && r.wood == 5 + 6 && r.mercury == 3 && r.sulfur == 7)
    #expect(r.ore == 0 && r.crystal == 0 && r.gem == 0)
    #expect(s.backpack(army: 0) == [77, 200, 55, -1])                   // pickup order; unknown static artifact -1
    #expect(s.removedObjects == Array(1...10))
    // the mine is never occupied: the army stops on the previous cell, the object stays
    _ = s.select(army: 0)
    #expect(s.plan(to: cell(14, 24)).ok)
    let m = s.move()
    #expect(m.ok && m.picked == nil && s.removedObjects == Array(1...10) && s.army(0)!.cell.r >= 13)
    #expect(s.currentPlan == nil)                                        // plan cleared after the move
    #expect(s.resources(player: 0) == r)
}

@Test func pickupGoesToTheOwnerOfTheArmy() {
    let s = session([armyObj(0, 0, owner: 2), armyObj(9, 9, owner: 5), obj("treasure", 0, 3)], players: [(2, true), (5, true)])
    _ = s.select(army: 0)
    s.plan(to: cell(0, 3))
    #expect(s.move().picked == 2)
    #expect(s.resources(player: 2)!.gold == 1000 && s.resources(player: 5)!.gold == 0)
}

@Test func pickupOnlyWhenTheLastStepIsTakenToday() {
    // 25 steps to the treasure at (0,25): its step is on day 1 -> the army walks the day-0 steps, nothing is picked
    let s = session([armyObj(0, 0), obj("treasure", 0, 25)])
    _ = s.select(army: 0)
    let p = s.plan(to: cell(0, 25))
    #expect(p.ok && p.dayOf.last == 1)
    let m = s.move()
    #expect(m.ok && m.picked == nil && m.steps == 23 && s.removedObjects.isEmpty && s.army(0)!.cell == cell(0, 23))
    s.endTurn()
    _ = s.select(army: 0)
    s.plan(to: cell(0, 25))
    #expect(s.move().picked == 1 && s.army(0)!.cell == cell(0, 24))
}

@Test func worldMutationMovesArmiesAndRemovesObjects() {
    let s = session([armyObj(5, 5, owner: 0), armyObj(0, 0, owner: 0), obj("treasure", 5, 10)], players: [(0, true)])
    _ = s.select(army: 0)
    s.plan(to: cell(5, 7)); _ = s.move()
    _ = s.select(army: 1)
    #expect(s.plan(to: cell(5, 7)).why == .goalArmy)                    // the moved army blocks its new cell
    #expect(s.plan(to: cell(5, 5)).ok)                                   // its old cell is free again
    #expect(s.plan(to: cell(5, 10)).ok)                                  // the treasure is a (terminal) destination
    _ = s.select(army: 0)
    s.plan(to: cell(5, 10)); #expect(s.move().picked == 2)
    _ = s.select(army: 1)
    let p = s.plan(to: cell(5, 10))                                      // the footprint is gone: an ordinary free cell
    #expect(p.ok && p.path.last == cell(5, 10))
    #expect(s.pickups(level: 0).isEmpty)
}

// MARK: - pickups(level:) and nearestPickup(for:)

@Test func pickupsListsTargetCells() {
    // 2x2 treasure at (2,2): entrances on the RIGHT edge of both cells of column y+1, UP edge of (2,3) and DOWN edge of (3,2)
    let eh: [Bool] = [false, false, false, false, true, true]            // line 0, 1, 2: only line 2 (cells (2,3), (3,3) from (x+i, 4))
    let ev: [Bool] = [false, true, false, false, true, false]            // i * H + j: line 0 j=1 (UP of (2,3)); line 2 j=0 (DOWN of (3,2))
    let objs = [
        armyObj(15, 15),
        obj("treasure", 2, 2, w: 2, h: 2, eh: eh, ev: ev),               // 1
        obj("campfire", 10, 10),                                         // 2
        obj("mine", 12, 12, model: "Mines.Ore"),                         // 3: not a pickup
        obj("random_artifact", 14, 4, resolved: H4ResolvedObject(model: "x", artifact: 3)),   // 4
        obj("random_artifact", 18, 4, resolved: H4ResolvedObject(model: "x")),                // 5: no artifact id -> no effect defined
        obj("material_pile", 20, 4, model: "Resources.Plutonium", sub: "unknown_pile"),       // 6: unknown resource
        obj("artifact", 22, 4, model: "artifacts.none"),                 // 7: id -1 still a pickup
    ]
    let s = session(objs)
    let l = s.pickups(level: 0)
    #expect(l.map(\.objectIndex) == [1, 2, 4, 7])
    #expect(l[0].targetCells == [cell(2, 3), cell(3, 2), cell(3, 3)])    // sorted by (row, column); (2,2) has no entrance
    // a 1x1 object with four entrance edges: its one cell, once
    #expect(l[1].targetCells == [cell(10, 10)])
    // an object nobody can step into is not listed: walled by water on all sides
    var water: Set<H4MoveCell> = []
    for r in 9...11 { for c in 9...11 where !(r == 10 && c == 10) { water.insert(cell(r, c)) } }
    let w = session(objs, water: water)
    #expect(w.pickups(level: 0).map(\.objectIndex) == [1, 4, 7])
    // a picked object is excluded
    _ = s.select(army: 0)
    s.plan(to: cell(10, 10)); _ = s.move()
    #expect(s.removedObjects == [2] && s.pickups(level: 0).map(\.objectIndex) == [1, 4, 7])
    // a removed object leaves the list even if it was the only one
    #expect(s.pickups(level: 1).isEmpty)
}

@Test func nearestPickupTieBreak() {
    // army at (5,5); treasures at (5,3) [index 2] and (5,7) [index 1]: both cost 200 -> lowest object index
    let s = session([armyObj(5, 5), obj("treasure", 5, 7), obj("treasure", 5, 3)])
    let n = s.nearestPickup(for: 0)
    _ = s.select(army: 0)
    #expect(s.plan(to: cell(5, 7)).cost == 200 && s.plan(to: cell(5, 3)).cost == 200)
    #expect(n?.objectIndex == 1 && n?.targetCell == cell(5, 7) && n?.cost == 200)
    // the same objects in the other order -> the other one wins
    let t = session([armyObj(5, 5), obj("treasure", 5, 3), obj("treasure", 5, 7)])
    #expect(t.nearestPickup(for: 0)?.objectIndex == 1 && t.nearestPickup(for: 0)?.targetCell == cell(5, 3))
    // equal cost within one object: lowest (row, column). 3x1 block (rows 4..6, column 7), entrances from the LEFT on rows 4 and 6
    let eh = [true, false, true, false, false, false]                    // line 0: ii = 0, 2 (cell (x+ii, y) from (x+ii, y-1))
    let ev = [Bool](repeating: false, count: 4)
    let u = session([armyObj(5, 4), obj("treasure", 4, 7, w: 3, h: 1, eh: eh, ev: ev)])
    let m = u.nearestPickup(for: 0)
    #expect(m?.objectIndex == 1 && m?.targetCell == cell(4, 7))
    _ = u.select(army: 0)
    #expect(u.plan(to: cell(4, 7)).cost == u.plan(to: cell(6, 7)).cost && u.plan(to: cell(6, 7)).ok)
    // a cheaper object beats a lower index
    let v = session([armyObj(5, 5), obj("treasure", 5, 12), obj("treasure", 5, 7)])
    #expect(v.nearestPickup(for: 0)?.objectIndex == 2)
}

@Test func nearestPickupNilWhenUnreachable() {
    // a water wall (column 10) cuts the level
    var wall: Set<H4MoveCell> = []
    for r in 0..<30 { wall.insert(cell(r, 10)) }
    let s = session([armyObj(5, 5), obj("treasure", 5, 15), obj("campfire", 8, 20)], water: wall)
    #expect(s.pickups(level: 0).map(\.objectIndex) == [1, 2])            // listed, but not reachable
    #expect(s.nearestPickup(for: 0) == nil)
    // reachable on the same side
    let t = session([armyObj(5, 5), obj("treasure", 5, 15), obj("campfire", 8, 8)], water: wall)
    #expect(t.nearestPickup(for: 0)?.objectIndex == 2)
    // no pickup at all, unknown army
    #expect(session([armyObj(5, 5)]).nearestPickup(for: 0) == nil)
    #expect(session([armyObj(5, 5), obj("treasure", 5, 7)]).nearestPickup(for: 9) == nil)
    // points left do not make a target unreachable (days are allowed): cost is the full cost
    let far = session([armyObj(0, 0), obj("treasure", 0, 28)])
    #expect(far.nearestPickup(for: 0)?.cost == 2800)
}

@Test func nearestPickupFromOwnStartCell() {
    // treasure at (5,6) enterable only from the left, i.e. from the army's own cell (5,5): no free cell can enter it, so
    // pickups(level:) leaves it out, but a plan from the army ends there and nearestPickup finds it
    let eh = [true, false], ev = [false, false]
    // (an entrance edge also admits the two diagonal neighbours on that side: (4,5) and (6,5) are water)
    let box: Set<H4MoveCell> = [cell(4, 5), cell(6, 5)]
    let s = session([armyObj(5, 5), obj("treasure", 5, 6, eh: eh, ev: ev)], water: box)
    #expect(s.pickups(level: 0).isEmpty)
    let n = s.nearestPickup(for: 0)
    _ = s.select(army: 0)
    let p = s.plan(to: cell(5, 6))
    #expect(p.ok && n?.objectIndex == 1 && n?.targetCell == cell(5, 6) && n?.cost == p.cost)
    #expect(s.move().picked == 1)
    // another army elsewhere has no way in: not its start cell, no free neighbour
    let t = session([armyObj(5, 5), armyObj(20, 20), obj("treasure", 5, 6, eh: eh, ev: ev)], water: box)
    #expect(t.nearestPickup(for: 0)?.objectIndex == 2)
    #expect(t.nearestPickup(for: 1) == nil)
}

@Test func scriptEchoesArgumentsOnAnyOp() throws {
    let s = session([armyObj(5, 5)])
    let out = try s.runScript(Data(#"[{"op":"state","army":297,"to":[1,1]},{"op":"endturn","army":"x"}]"#.utf8))
    #expect(out.hasPrefix(#"[{"army":297,"#) && out.contains(#""to":[1,1]"#) && out.contains(#""army":"x""#))
    #expect(throws: (any Error).self) { try session([armyObj(5, 5)]).runScript(Data(#"[{"op":"state","army":297.5}]"#.utf8)) }
}

// MARK: - Arrows (rule 6)

@Test func arrowTurnTable() throws {
    func path(_ dirs: [Int], from: H4MoveCell = cell(10, 10)) -> [H4MoveCell] {
        var out = [from]
        for d in dirs { out.append(cell(out.last!.r + H4MoveWorld.dirs[d].dr, out.last!.c + H4MoveWorld.dirs[d].dc)) }
        return out
    }
    func names(_ dirs: [Int], day: [Int]? = nil) -> [String]? { H4PathArrows.names(path: path(dirs), dayOf: day ?? [Int](repeating: 0, count: dirs.count)) }
    #expect(names([]) == [] && names([2]) == ["internal.green_arrow.dest"])
    #expect(names([2, 2, 2]) == ["internal.green_arrow.straight.se", "internal.green_arrow.straight.se", "internal.green_arrow.dest"])
    // turn = (out - in) mod 8: 1 right, 7 left, the rest straight; the suffix is the outgoing direction
    for inn in 0..<8 {
        for out in 0..<8 {
            let n = names([inn, out])!
            let turn = (out - inn + 8) % 8
            let kind = turn == 1 ? "right" : turn == 7 ? "left" : "straight"
            #expect(n[0] == "internal.green_arrow.\(kind).\(H4PathArrows.directionNames[out])", "in \(inn) out \(out)")
        }
    }
    #expect(names([2, 3])![0] == "internal.green_arrow.right.s" && names([3, 2])![0] == "internal.green_arrow.left.se")
    // colour = day of the step that arrives on the cell
    #expect(names([2, 2, 2], day: [0, 1, 1]) == ["internal.green_arrow.straight.se", "internal.red_arrow.straight.se", "internal.red_arrow.dest"])
    #expect(names([2, 2], day: [0, 0]) == ["internal.green_arrow.straight.se", "internal.green_arrow.dest"])
    #expect(names([2], day: [1]) == ["internal.red_arrow.dest"])
    // non-adjacent cells / short day list are rejected
    #expect(H4PathArrows.names(path: [cell(0, 0), cell(0, 2), cell(0, 3)], dayOf: [0, 0]) == nil)
    #expect(H4PathArrows.names(path: [cell(0, 0), cell(0, 1)], dayOf: []) == nil)
    #expect(H4PathArrows.allNames.count == 2 * (1 + 3 * 8) && Set(H4PathArrows.allNames).count == 50)
}

@Test func planCarriesArrows() {
    let s = session([armyObj(0, 0)])
    _ = s.select(army: 0)
    let p = s.plan(to: cell(2, 2))                                        // pure diagonal S, S
    #expect(p.arrows == ["internal.green_arrow.straight.s", "internal.green_arrow.dest"])
    let st = s.renderState
    #expect(st.arrows.map(\.model) == p.arrows && st.arrows.map(\.cell) == [cell(1, 1), cell(2, 2)])
    _ = s.move()
    #expect(s.renderState.arrows.isEmpty && s.renderState.armyCells[0] == cell(2, 2))
    #expect(s.plan(to: cell(99, 99)).arrows.isEmpty)
}

// MARK: - Script runner (rules 7 and 8)

@Test func scriptLogSchema() throws {
    let s = session([armyObj(5, 5), obj("treasure", 5, 7)])
    let script = #"[{"op":"plan","to":[5,7]},{"op":"select","army":0},{"op":"plan","to":[5,7]},{"op":"move"},{"op":"endturn"},{"op":"state"}]"#
    let text = try s.runScript(Data(script.utf8))
    let log = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    #expect(log.count == 6)
    #expect(log[0]["why"] as? String == "no-selection" && log[0]["path"] == nil && log[0]["to"] as? [Int] == [5, 7] && log[0]["ok"] as? Bool == false)
    #expect(log[1]["ok"] as? Bool == true && log[1]["why"] is NSNull && log[1]["army"] as? Int == 0 && log[1]["cell"] as? [Int] == [5, 5])
    #expect(log[2]["cost"] as? Int == 200 && (log[2]["arrows"] as? [String])?.last == "internal.green_arrow.dest")
    #expect(log[3]["steps"] as? Int == 2 && log[3]["picked"] as? Int == 1 && log[3]["spent"] as? Int == 200 && log[3]["points"] as? Int == 2056)
    #expect(log[4]["selected"] is NSNull && log[4]["day"] as? Int == 2)
    #expect((log[5]["removed"] as? [Int]) == [1] && ((log[5]["resources"] as? [String: Any])?["0"] as? [String: Int])?["gold"] == 1000)
    // keys sorted, compact, no trailing newline
    #expect(text.hasPrefix(#"[{"backpacks":{},"cell":null,"day":1,"level":null,"month":1,"ok":false,"op":"plan","#) && !text.hasSuffix("\n") && !text.contains(", ") && !text.contains(": "))
    #expect(throws: H4Error.self) { try s.runScript(Data(#"[{"op":"dance"}]"#.utf8)) }
}

// MARK: - Real data

private func loadOracle(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: env["H4_SESSION_ORACLE_DIR"]! + "/" + name))
}

private struct Started {
    let store: H4ResourceStore, tables: H4GameTables, scenario: H4Scenario, game: H4Game
    init(map: String) throws {
        store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!))
        tables = try H4GameTables(store: store)
        let host = try H4MovementSession(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!), mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!))
        let files = try #require(host.mapFiles[map])
        #expect(files.count == 1)
        scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: files[0])))
        game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: 12345, difficulty: 2)
    }
    func session() throws -> H4GameSession { try H4GameSession(game: game, scenario: scenario, resources: store, tables: tables) }
}

private let oracleMaps = [("s1", "Ancestral_Home"), ("s2", "Dannte"), ("s3", "Heart_of_Winter"), ("s4", "Bandits_of_the_Rifen_Maze"), ("s5", "Land_of_the_Lamp")]

@Test(.enabled(if: hasOracle), arguments: oracleMaps)
func scriptsReproduceTheFrozenLogs(entry: (String, String)) throws {
    let st = try Started(map: entry.1)
    let text = try st.session().runScript(loadOracle("scripts/\(entry.0).json"))
    #expect(Data(text.utf8) == (try loadOracle("logs/\(entry.0).json")), "\(entry.0) \(entry.1)")
}

@Test(.enabled(if: hasOracle))
func arrowsOf10CasesExistInTheStore() throws {
    let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!))
    let cases = try #require(try JSONSerialization.jsonObject(with: loadOracle("arrows10.json")) as? [[String: Any]])
    #expect(cases.count == 10)
    for c in cases {
        let path = (c["path"] as! [[Int]]).map { cell($0[0], $0[1]) }
        let got = H4PathArrows.names(path: path, dayOf: c["day_of"] as! [Int])
        #expect(got == (c["expected"] as! [String]), "case \(c["id"] ?? "?")")
        for n in got ?? [] { #expect(store.locate("adv_object.\(n).h4d") != nil, "missing adv_object.\(n)") }
    }
    for n in H4PathArrows.allNames { #expect(store.locate("adv_object.\(n).h4d") != nil, "missing adv_object.\(n)") }
}

/// Replays s1 up to and including its first pickup (command 3, object 871) and its next plan (command 4); the draw list
/// then equals the 7c list except for the army, the picked object and the arrows.
@Test(.enabled(if: hasOracle))
func sessionDrawListDeltas() throws {
    let st = try Started(map: "Ancestral_Home")
    let s = try st.session()
    let models = H4ObjectModelLibrary(store: st.store)
    let render = H4GameRender(store: st.store, tables: st.tables, models: models)
    let region = H4MapTerrainRender.Region(row: 36, column: 40, rows: 40, columns: 40)
    let objects = s.scenarioObjects
    let base = try render.drawList(objects: objects, game: st.game, level: 0, region: region)
    // a fresh session renders as 7c
    let fresh = try render.drawList(objects: objects, game: st.game, level: 0, region: region, state: s.renderState)
    func key(_ i: H4ObjectDrawItem) -> String { "\(i.kind.rawValue) \(i.model) \(i.x),\(i.y) \(i.layerIndex) \(i.column.map(String.init) ?? "-") \(i.left),\(i.top)" }
    #expect(fresh.items.map(key) == base.items.map(key) && fresh.objectCount == base.objectCount && fresh.armyCount == base.armyCount)

    let script = try #require(try JSONSerialization.jsonObject(with: loadOracle("scripts/s1.json")) as? [[String: Any]])
    let log = try #require(try JSONSerialization.jsonObject(with: loadOracle("logs/s1.json")) as? [[String: Any]])
    var records: [[String: Any]] = []
    for c in script[0...4] { records.append(try JSON(s.run(command: c))) }
    func JSON(_ j: H4LogJSON) throws -> [String: Any] { try #require(try JSONSerialization.jsonObject(with: Data(j.text.utf8)) as? [String: Any]) }
    #expect(records[3]["picked"] as? Int == 871 && (log[3]["picked"] as? Int) == 871)
    let oldCell = cell(47, 55), newCell = cell(50, 56)
    #expect(records[3]["cell"] as? [Int] == [50, 56] && s.army(297)?.cell == newCell)

    let l = try render.drawList(objects: objects, game: st.game, level: 0, region: region, state: s.renderState)
    let picked = objects[871]
    let pickedModel = st.game.objects.first { $0.index == 871 }?.resolved.model ?? picked.modelName
    func isArmy(_ i: H4ObjectDrawItem, at c: H4MoveCell) -> Bool { i.x == c.r && i.y == c.c && (i.model.hasPrefix("adv_actor.") || i.kind == .flag) }
    func isPicked(_ i: H4ObjectDrawItem) -> Bool { i.x == Int(picked.x) && i.y == Int(picked.y) && (i.model == pickedModel || i.kind == .flag) }
    func isArrow(_ i: H4ObjectDrawItem) -> Bool { i.model.hasPrefix("internal.") }
    let baseOld = base.items.filter { isArmy($0, at: oldCell) }
    let baseRest = base.items.filter { !isArmy($0, at: oldCell) && !isPicked($0) }.map(key)
    let lNew = l.items.filter { isArmy($0, at: newCell) }
    let lRest = l.items.filter { !isArmy($0, at: newCell) && !isArrow($0) }.map(key)
    #expect(!baseOld.isEmpty && baseOld.count < base.items.count)
    #expect(base.items.contains { isPicked($0) } && !l.items.contains { isPicked($0) })        // the picked object's items are gone
    #expect(lRest == baseRest)                                                                  // everything else: same items, same order
    // the army's items moved with the same layers/columns and the anchor offset
    let a0 = H4MapObjectRender.anchor(x: oldCell.r, y: oldCell.c, region: region), a1 = H4MapObjectRender.anchor(x: newCell.r, y: newCell.c, region: region)
    func shape(_ i: H4ObjectDrawItem, dx: Int, dy: Int, cx: Int, cy: Int) -> String {
        "\(i.kind.rawValue) \(i.model) \(i.layerIndex) \(i.column.map(String.init) ?? "-") \(i.left - dx),\(i.top - dy) \(i.x - cx),\(i.y - cy)"
    }
    #expect(baseOld.map { shape($0, dx: a0.x, dy: a0.y, cx: oldCell.r, cy: oldCell.c) }.sorted()
            == lNew.map { shape($0, dx: a1.x, dy: a1.y, cx: newCell.r, cy: newCell.c) }.sorted())
    // arrows: the logged names at the cells of the plan, after all the other items
    let names = try #require(records[4]["arrows"] as? [String])
    let path = try #require(records[4]["path"] as? [[Int]]).map { cell($0[0], $0[1]) }
    #expect(names.count == 9 && path.count == 10 && path[0] == newCell)
    let arrowItems = l.items.filter(isArrow)
    #expect(!arrowItems.isEmpty)
    var seen = Set<String>()
    for (n, c) in zip(names, path.dropFirst()) where arrowItems.contains(where: { $0.model == n && $0.x == c.r && $0.y == c.c }) { seen.insert("\(n)@\(c.r),\(c.c)") }
    #expect(seen.count == Set(zip(names, path.dropFirst()).map { "\($0)@\($1.r),\($1.c)" }).count, "every logged arrow is drawn at its plan cell")
    #expect(Set(arrowItems.map { "\($0.model)@\($0.x),\($0.y)" }) == seen)
    #expect(models.missingModels.isEmpty && render.missingActors.isEmpty)
}

/// The nearest pickup of the first army on real maps agrees with a plan to its target cell (same cost) and walking there
/// collects it (within a few days).
@Test(.enabled(if: hasOracle), arguments: oracleMaps)
func nearestPickupAgreesWithPlanOnRealMaps(entry: (String, String)) throws {
    let st = try Started(map: entry.1)
    let s = try st.session()
    guard let army = s.armies.first(where: { $0.owner == s.currentPlayer }) else { return }
    #expect(!s.pickups(level: army.level).isEmpty)
    let near = try #require(s.nearestPickup(for: army.id))
    #expect(s.select(army: army.id).isOK)
    let p = s.plan(to: near.targetCell)
    #expect(p.ok && p.cost == near.cost)
    var picked: Int?
    for _ in 0..<10 where picked == nil {
        if !s.plan(to: near.targetCell).ok { break }
        picked = s.move().picked
        if picked == nil { s.endTurn(); _ = s.select(army: army.id) }
    }
    #expect(picked != nil)            // normally the target itself; overlapping footprints may resolve to another object
    #expect(picked.map { s.removedObjects.contains($0) } == true)
}

private extension Result where Success == Void {
    var isOK: Bool { if case .success = self { return true }; return false }
}

/// The selection ring is a ground model (O4): it is drawn before the body strips of the army on its cell; the path arrows
/// (not ground models) stay after everything.
@Test(.enabled(if: hasOracle))
func selectionRingIsDrawnUnderTheArmy() throws {
    let st = try Started(map: "Ancestral_Home")
    let s = try st.session()
    let models = H4ObjectModelLibrary(store: st.store)
    let render = H4GameRender(store: st.store, tables: st.tables, models: models)
    let region = H4MapTerrainRender.Region(row: 36, column: 40, rows: 40, columns: 40)
    let ring = try #require(try models.model(named: "internal.selected.army"))
    #expect(ring.imageKind == 1 || ring.drawLayer == 2)
    let c = try #require(s.army(297)?.cell)
    var state = s.renderState
    state.arrowLevel = 0
    state.arrows = [(cell: c, model: "internal.selected.army")]
    let l = try render.drawList(objects: s.scenarioObjects, game: st.game, level: 0, region: region, state: state)
    let at = l.items.enumerated().filter { $0.element.x == c.r && $0.element.y == c.c }
    let ringIdx = try #require(at.first { $0.element.model == "internal.selected.army" && $0.element.kind == .body }?.offset)
    let armyBodies = at.filter { $0.element.model.hasPrefix("adv_actor.") && $0.element.kind == .body }.map(\.offset)
    #expect(!armyBodies.isEmpty && armyBodies.allSatisfy { ringIdx < $0 })
}
