import Foundation
import Testing
@testable import H4Kit

@Test func mapGeometryMatchesTheGame() {
    let g = H4MapGeometry(size: 152)
    // Values measured on "A Land without a King": a 152-row diamond of 11,704 cells.
    #expect(g.cellRows.count == 152 && g.cellCount == 11_704)
    #expect(g.cellRows[0] == 75..<77 && g.cellRows[75] == 0..<152 && g.cellRows[151] == 75..<77)
    #expect(g.vertexRows.count == 153)
    #expect(g.vertexRows[0] == 75..<78 && g.vertexRows[1] == 74..<79)
    for size in [4, 76, 152, 228, 304] {
        let s = H4MapGeometry(size: size)
        #expect(s.cellRows.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= size })
        #expect(s.cellRows.indices.allSatisfy { s.cellRows[$0].count == s.cellRows[size - 1 - $0].count })
    }
}

/// Version-29 scenario header with one human player.
func scenarioHeader(size: Int, levels: Int) -> Data {
    var h = le16(29) + le16(0) + le16(UInt16(size))
    h += Data([UInt8(levels)]) + le32(0) + Data([1, 0, 1, 0, 0, 0x3F])
    h += str16("t") + Data([0]) + str16("")
    h += le16(0) + Data([0, 0, 0, 1]) + Data([0, 0]) + str16("") + Data([0])
    return h
}

/// Builds a scenario body: unreadable "object" bytes, then terrain cells, then corner heights.
func terrainScenario(size: Int, levels: Int = 1, junk: Data = Data(repeating: 0xFF, count: 37)) -> (H4Scenario, [UInt8]) {
    let g = H4MapGeometry(size: size)
    var cells = Data(), types: [UInt8] = []
    for _ in 0..<levels {
        for (r, range) in g.cellRows.enumerated() {
            for c in range {
                let t = UInt8((r + c) % 9)
                types.append(t)
                cells += Data([t, UInt8(c % 2), 1, 2, 1]) + le32(0x80000)   // type, variant, a, b, c, flags
                if c == range.lowerBound {
                    cells += Data([1, 7, 0]) + le16(5) + Data([9])           // one overlay
                    cells += Data([1, 2]) + le16(3) + Data([4])              // one road
                } else {
                    cells += Data([0, 0])
                }
            }
        }
    }
    let heights = Data((0..<(levels * g.vertexCount)).map { UInt8($0 % 251) })
    let scenario = try! H4Scenario(scenario: scenarioHeader(size: size, levels: levels) + junk + cells + heights,
                                   containerVersion: 22)
    return (scenario, types)
}

@Test func locatesTerrainBehindUnparsedObjects() throws {
    let (scenario, types) = terrainScenario(size: 8, levels: 2)
    let t = try H4ScenarioTerrain(scenario: scenario)
    #expect(t.start == 37 && t.alternativeStarts.isEmpty && t.uncertainCells == 0)
    let decoded = t.cells.flatMap { $0.flatMap { $0.map(\.terrain) } }
    #expect(decoded == types)
    let first = t.cells[0][0][0]
    #expect(first.overlays == [.init(terrain: 7, variant: 0, value: 5, extra: 9)])
    #expect(first.roads == [.init(kind: 2, value: 3, extra: 4)])
    #expect(t.heights[1].last?.last == UInt8((2 * t.geometry.vertexCount - 1) % 251))
    #expect(t.cell(level: 0, row: 0, column: 0) == nil)            // outside the diamond
    let map = t.minimap(level: 0) { _ in (1, 2, 3) }
    #expect(map.width > 0 && map.pixels.contains(3))
}

@Test func rejectsScenarioWithoutTerrain() {
    var (scenario, _) = terrainScenario(size: 8)
    // Corrupt every cell type: no offset can decode any more.
    var body = scenario.body
    for i in body.indices where body[i] < 9 { body[i] = 0xEE }
    scenario = try! H4Scenario(scenario: scenarioHeader(size: 8, levels: 1) + body, containerVersion: 22)
    #expect(throws: (any Error).self) { try H4ScenarioTerrain(scenario: scenario) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realScenarioTerrain() throws {
    let maps = URL(fileURLWithPath: ProcessInfo.processInfo.environment["H4_DATA_DIR"]!)
        .deletingLastPathComponent().appendingPathComponent("maps")
    let king = try H4ScenarioTerrain(scenario: H4Scenario(fileData: Data(contentsOf: maps.appendingPathComponent("A Land without a King.h4c"))))
    #expect(king.start == 233_260 && king.alternativeStarts.isEmpty)
    let counts = Dictionary(grouping: king.cells[0].flatMap { $0 }, by: \.terrain).mapValues(\.count)
    #expect(counts[0] == 3350 && counts[1] == 2809 && counts[7] == 2639)   // water, grass, dirt
    let home = try H4ScenarioTerrain(scenario: H4Scenario(fileData: Data(contentsOf: maps.appendingPathComponent("Ancestral Home.h4c"))))
    #expect(home.levels == 2 && home.cells[1].flatMap { $0 }.contains { $0.terrain == 8 })  // underground level
}

/// Regression: an all-zero body decodes from every offset; the old search re-decoded the whole
/// map from each one (42 s for a 533-byte file). The linear search must stay fast.
@Test func hostileUniformBodyIsFast() throws {
    let g = H4MapGeometry(size: 152)
    let body = Data(count: g.cellCount * 11 + g.vertexCount + 300)
    let scenario = try H4Scenario(scenario: scenarioHeader(size: 152, levels: 1) + body, containerVersion: 22)
    let clock = ContinuousClock()
    let elapsed = try clock.measure { _ = try H4ScenarioTerrain(scenario: scenario) }
    #expect(elapsed < .seconds(2))
    let huge = try H4Scenario(scenario: scenarioHeader(size: 1024, levels: 2) + Data(count: 64), containerVersion: 22)
    #expect(throws: (any Error).self) { try H4ScenarioTerrain(scenario: huge) }
}

@Test func cellValidationFollowsTheGame() {
    func read(_ bytes: [UInt8]) -> H4TerrainCell? {
        bytes.withUnsafeBytes { d in var o = 0; return H4TerrainCell.read(d, &o, recordVersion: 4, limit: bytes.count) }
    }
    let base: [UInt8] = [1, 0, 0, 0, 7, 0, 0, 8, 0, 0]                    // c = 7: the game only tests ≠ 0
    #expect(read(base + [0])?.c == true)
    #expect(read(base + [1, 3, 0, 0, 0]) != nil)                          // road kind 3 accepted
    #expect(read(base + [1, 4, 0, 0, 0]) == nil)                          // road kind 4 rejected (0x413fbe)
    #expect(read([19, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0]) == nil)               // terrain 19 has no variant
}
