import Foundation
import Testing
@testable import H4Kit

// Slice 7b: movement. The synthetic tests mirror the 29 checks of `move_ref.py --selftest`. The data-gated tests read
// H4_DATA_DIR (Data folder), H4_MAPS_DIR (maps folder) and H4_MOVE_ORACLE_DIR (folder with the frozen queries.json,
// answers.json and towns_ref.json).

private let env = ProcessInfo.processInfo.environment
private let hasOracle = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil && env["H4_MOVE_ORACLE_DIR"] != nil

private typealias Terr = [H4MoveCell: UInt8]

/// 6x6 synthetic level: grass (terrain 1) unless overridden.
private func mk(terr: Terr = [:], road: Terr = [:], rock: Terr = [:], placed: [H4MovePlaced] = []) -> H4MoveWorld {
    H4MoveWorld(size: 6, rows: Array(repeating: 0..<6, count: 6), cell: { r, c in
        let k = H4MoveCell(r, c)
        return (terr[k] ?? 1, road[k] ?? 0, rock[k] ?? 0)
    }, placed: placed)
}

private func cell(_ r: Int, _ c: Int) -> H4MoveCell { H4MoveCell(r, c) }

private func q(_ w: H4MoveWorld, _ a: (Int, Int), _ b: (Int, Int), points: Int = 2256, full: Int = 2256) -> H4MoveAnswer {
    w.query(from: cell(a.0, a.1), to: cell(b.0, b.1), points: points, full: full)
}

private func object(_ cls: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int, b: [Bool], eh: [Bool]? = nil, ev: [Bool]? = nil) -> H4MovePlaced {
    H4MovePlaced(className: cls, x: x, y: y, footprint: H4MoveFootprint(width: w, height: h, blocked: b, edgesHorizontal: eh, edgesVertical: ev))
}

@Test func movementCostsAndTerrain() {
    let w = mk()
    var r = q(w, (0, 0), (0, 3))                       // along a row: SE steps (0,+1) are direction 2, 3 x 100
    #expect(r.cost == 300 && r.days == 1)
    r = q(w, (0, 0), (3, 3))                           // pure diagonal: 3 x 150
    #expect(r.cost == 450 && r.path.count == 4)
    #expect(q(mk(terr: [cell(0, 1): 3]), (0, 0), (0, 1)).cost == 200)
    let wr = mk(road: [cell(0, 0): 1, cell(0, 1): 2, cell(0, 2): 3, cell(0, 3): 1])
    #expect(q(wr, (0, 0), (0, 1)).cost == 100)
    #expect(q(wr, (0, 1), (0, 2)).cost == 75)
    #expect(q(wr, (0, 0), (0, 3)).cost == 100 + 75 + 75)
    #expect(q(mk(road: [cell(0, 1): 1]), (0, 0), (0, 1)).cost == 100)   // a road needs both cells
    #expect(q(mk(road: [cell(0, 0): 1, cell(1, 1): 1]), (0, 0), (1, 1)).cost == 75 + 37)
}

@Test func movementBlockedAndCornerCutting() {
    let rock: Terr = [cell(0, 1): 1, cell(1, 0): 1, cell(1, 1): 1]
    #expect(q(mk(rock: rock), (0, 0), (0, 2)).reachable == false)
    let water: Terr = [cell(0, 1): 0, cell(1, 0): 0, cell(1, 1): 0]
    #expect(q(mk(terr: water), (0, 0), (0, 2)).why == .noPath)
    #expect(q(mk(rock: [cell(0, 1): 1, cell(1, 0): 1]), (0, 0), (1, 1)).cost == 150)   // corner cutting
}

@Test func movementDaySplit() {
    func split(_ costs: [Int], _ p: Int) -> ([Int], Int) { let r = H4MoveWorld.daySplit(costs: costs, points: p, full: 2256); return (r.dayOf, r.days) }
    #expect(split([100, 100, 100], 250) == ([0, 0, 0], 1))
    #expect(split([100, 100, 100, 100], 250) == ([0, 0, 0, 1], 2))
    #expect(split([100, 100], 200) == ([0, 0], 1))          // exact exhaustion on the last step adds no day
    #expect(split([100, 100, 100], 200) == ([0, 0, 1], 2))  // c >= rem is a rollover
    #expect(split([100], 0) == ([1], 2))                    // zero points rests a day
    #expect(split([], 100) == ([], 0))
}

@Test func movementObjectEntrances() {
    // 2x1 block at (2,2),(3,2); the only entrance is the DOWN side of cell i=1, i.e. from (4,2)
    let wo = mk(placed: [object("treasure", 2, 2, 2, 1, b: [true, true], eh: [false, false, false, false], ev: [false, false, true])])
    #expect(q(wo, (5, 2), (3, 2)).reachable)
    #expect(q(wo, (5, 2), (3, 2)).path.dropLast().last?.r == 4)
    #expect(q(wo, (0, 2), (2, 2)).reachable == false)
    #expect(q(wo, (3, 1), (3, 2)).path.dropLast().last?.r == 4)         // no entrance from the left: detour below
    #expect(q(wo, (4, 1), (3, 2)).reachable)                            // diagonal entry through the DOWN edge
    let r = q(wo, (4, 2), (1, 2))                                       // the terminal object cannot be crossed
    #expect(r.reachable && !r.path.contains(cell(3, 2)) && !r.path.contains(cell(2, 2)))
    let wt = mk(placed: [object("treasure", 3, 3, 1, 1, b: [true], eh: [true, true], ev: [true, true])])
    let t = q(wt, (0, 3), (5, 3))
    #expect(t.reachable && !t.path.contains(cell(3, 3)))                // terminal cell not crossed
    #expect(q(wt, (0, 3), (3, 3)).reachable)                            // goal on a pickup
    #expect(q(wt, (3, 3), (3, 4)).reachable)                            // the start cell is expanded
}

@Test func movementArmiesAndDecks() {
    let wa = mk(placed: [H4MovePlaced(armyAt: 2, 2)])
    #expect(q(wa, (0, 0), (2, 2)).why == .goalArmy)
    #expect(q(wa, (2, 2), (2, 3)).cost == 100)                          // start on an army cell
    var water: Terr = [:]
    for r in 0..<6 { water[cell(r, 1)] = 0; water[cell(r, 2)] = 0 }
    let wd = mk(terr: water, placed: [object("bridge", 2, 1, 1, 3, b: [true, true, true])])
    #expect(q(wd, (2, 0), (2, 3)).cost == 75 * 3)
    #expect(q(wd, (0, 0), (0, 3)).path.contains(cell(2, 1)))            // the only crossing is the bridge
}

@Test func movementOutputSchemaAndFailures() {
    let w = mk(rock: [cell(5, 5): 1])
    #expect(q(w, (0, 0), (0, 0)) == H4MoveAnswer(reachable: true, cost: 0, days: 0, path: [cell(0, 0)], dayOf: [], why: nil))
    #expect(q(w, (5, 5), (0, 0)).why == .startInvalid)
    #expect(q(w, (0, 0), (9, 9)).why == .goalOutOfMap)
    #expect(q(w, (0, 0), (5, 5)).why == .goalBlocked)
    #expect(q(w, (0, 0), (0, 2)).canonicalJSON == "{\"cost\":200,\"day_of\":[0,0],\"days\":1,\"path\":[[0,0],[0,1],[0,2]],\"reachable\":true}")
    #expect(q(w, (0, 0), (9, 9)).canonicalJSON == "{\"cost\":-1,\"day_of\":[],\"days\":-1,\"path\":[],\"reachable\":false,\"why\":\"goal-oob\"}")
}

@Test func movementTreeEqualsSingleGoalSearch() {
    let w = mk(terr: [cell(1, 1): 3, cell(2, 2): 2], road: [cell(0, 0): 1, cell(0, 1): 2])
    let tree = w.tree(from: cell(0, 0))
    for r in 0..<6 { for c in 0..<6 {
        #expect(w.query(from: cell(0, 0), to: cell(r, c), tree: tree) == w.query(from: cell(0, 0), to: cell(r, c)))
    } }
}

@Test func movementMapNameRule() {
    #expect(H4MovementSession.mapName(ofFile: "Contest Maps/Zanfas's Challenge.h4c") == "Zanfas's_Challenge")
    #expect(H4MovementSession.mapName(ofFile: "/a b/Shadowsinforest.h4c") == "Shadowsinforest")
}

// MARK: - Oracle (real data)

private func oracleFile(_ name: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: env["H4_MOVE_ORACLE_DIR"]! + "/" + name)) }

private func session() throws -> H4MovementSession {
    try H4MovementSession(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!), mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!))
}

@Test(.enabled(if: hasOracle)) func movementMatchesFrozenAnswers() throws {
    let text = try session().answersJSON(queries: oracleFile("queries.json"))
    #expect(Data(text.utf8) == (try oracleFile("answers.json")))
}

@Test(.enabled(if: hasOracle)) func movementTownsMatchFrozenReference() throws {
    let text = try session().townsJSON()
    #expect(Data(text.utf8) == (try oracleFile("towns_ref.json")))
}

/// Timed region: single-goal search of query #17 (Zanfas's Challenge L0 (97,221) -> (280,152)), path and day split;
/// the world construction is reported separately.
@Test(.enabled(if: hasOracle)) func movementBenchmarkQuery17() throws {
    let queries = try #require(try JSONSerialization.jsonObject(with: oracleFile("queries.json")) as? [[String: Any]])
    let answers = try #require(try JSONSerialization.jsonObject(with: oracleFile("answers.json")) as? [[String: Any]])
    let qy = queries[17]
    let from = try #require(qy["from"] as? [Int]), to = try #require(qy["to"] as? [Int])
    let points = try #require(qy["points"] as? Int), level = try #require(qy["level"] as? Int)
    let map = try session().map(named: try #require(qy["map"] as? String))

    func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
    let t0 = now()
    let world = try map.world(level: level)
    let build = now() - t0

    var times: [Double] = []
    var answer: H4MoveAnswer?
    for _ in 0..<20 {
        let t = now()
        answer = world.query(from: cell(from[0], from[1]), to: cell(to[0], to[1]), points: points)
        times.append(now() - t)
    }
    times.sort()
    let median = (times[9] + times[10]) / 2
    print("movementBenchmarkQuery17: world build \(build) ms, median of 20 searches \(median) ms (min \(times[0]), max \(times[19]))")
    let a = try #require(answer)
    #expect(a.reachable && a.cost == answers[17]["cost"] as? Int && a.days == answers[17]["days"] as? Int)
    #expect(a.cost == 27491 && a.days == 12)
    #expect(median < 50)
}
