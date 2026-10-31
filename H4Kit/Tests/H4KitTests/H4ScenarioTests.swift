import Foundation
import Testing
@testable import H4Kit

func scenarioBody(version: UInt16 = 29, cinematic: Bool = false, badCinematicVersion: Bool = false) -> Data {
    var d = le16(version)
    if version >= 28 { d += le16(7) }
    d += le16(76) + Data([2]) + le32(0x6BFC) + Data([2])
    d += Data([0, 1, 0, 0, 0x3F]) + Data([3, 0, 0, 0, 0x3F])        // two players, first human
    d += str16("Une terre sans Roi") + Data([1]) + str16("Le roi déclara…".data(using: .windowsCP1252).map { String(decoding: $0, as: UTF8.self) } ?? "")
    d += le16(0) + Data([2, 0b01, 0b10])                            // two teams
    d += Data([1]) + str16("Gagner") + Data([0])                    // victory text, no defeat text
    if version >= 25 { d += Data([1]) }
    if version >= 24 {
        // victory block (optionally set), defeat block unset
        d += cinematic ? Data([1]) + le16(badCinematicVersion ? 1 : 0) + str16("Bravo") + str16("last_stand") + str16("") : Data([0])
        d += Data([0])
    }
    if version >= 27 { d += str16("") }
    if version >= 29 { d += Data([0]) }
    return d + Data([0xAA, 0xBB])                                   // start of the scenario body
}

func scenarioFile(_ body: Data, container: UInt32 = 22, campaign: UInt8 = 0) -> Data {
    Data("H4CAMPAIGN".utf8) + le32(container) + Data([campaign]) + gzipped(body)
}

@Test func readsScenarioContainerAndHeader() throws {
    let s = try H4Scenario(fileData: scenarioFile(scenarioBody()))
    #expect(s.version == 29 && s.size == 76 && s.levels == 2)
    #expect(s.players.count == 2 && s.players[0].humanPlayable && !s.players[1].humanPlayable)
    #expect(s.players[1].colour == 3 && s.players[0].alignments == 0x3F)
    #expect(s.name == "Une terre sans Roi" && s.difficulty == 1)
    #expect(s.teams == [1, 2] && s.victoryText == "Gagner" && s.defeatText == nil)
    #expect(s.body == Data([0xAA, 0xBB]))
    let v27 = try H4Scenario(fileData: scenarioFile(scenarioBody(version: 27)))
    #expect(v27.version == 27 && v27.body == Data([0xAA, 0xBB]))
}

@Test func readsVictoryAndDefeatCinematics() throws {
    let s = try H4Scenario(fileData: scenarioFile(scenarioBody(cinematic: true)))
    #expect(s.victoryCinematic == .init(text: "Bravo", movie: "last_stand", secondName: ""))
    #expect(s.defeatCinematic == nil && s.body == Data([0xAA, 0xBB]))
    let plain = try H4Scenario(fileData: scenarioFile(scenarioBody()))
    #expect(plain.victoryCinematic == nil && plain.defeatCinematic == nil)
    // Before version 24 the blocks do not exist.
    let v23 = try H4Scenario(scenario: scenarioBody(version: 23), containerVersion: 22)
    #expect(v23.victoryCinematic == nil)
}

@Test func rejectsBadScenarios() {
    #expect(throws: (any Error).self) { try H4Scenario(fileData: Data("H4SAVEGAME".utf8) + le32(22) + Data([0])) }
    #expect(throws: (any Error).self) { try H4Scenario(fileData: scenarioFile(scenarioBody(), container: 23)) }
    #expect(throws: (any Error).self) { try H4Scenario(fileData: scenarioFile(scenarioBody(), campaign: 1)) }
    #expect(throws: (any Error).self) { try H4Scenario(fileData: scenarioFile(scenarioBody(version: 30))) }
    #expect(throws: (any Error).self) { try H4Scenario(fileData: scenarioFile(scenarioBody(cinematic: true, badCinematicVersion: true))) }
    let ok = scenarioFile(scenarioBody())
    #expect(throws: (any Error).self) { try H4Scenario(fileData: ok.prefix(ok.count - 1)) }   // broken gzip trailer
    // A forged trailer claiming 4 GB must be refused before any allocation.
    var huge = ok
    huge.replaceSubrange((huge.count - 4)..<huge.count, with: le32(0xFFFF_FFF0))
    #expect(throws: (any Error).self) { try H4Scenario(fileData: huge) }
}

/// Real scenarios, when H4_DATA_DIR points at the GOG "Data" folder (maps are in ../maps).
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realScenarios() throws {
    let maps = URL(fileURLWithPath: ProcessInfo.processInfo.environment["H4_DATA_DIR"]!)
        .deletingLastPathComponent().appendingPathComponent("maps")
    let files = try FileManager.default.contentsOfDirectory(at: maps, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "h4c" }
    #expect(files.count == 85)
    for f in files { _ = try H4Scenario(fileData: Data(contentsOf: f)) }
    let king = try H4Scenario(fileData: Data(contentsOf: maps.appendingPathComponent("A Land without a King.h4c")))
    #expect(king.name == "Une terre sans Roi" && king.size == 152 && king.levels == 1)
    #expect(king.players.map(\.colour) == [0, 1, 2] && king.teams == [2, 4, 1])
    #expect(king.description.hasPrefix("Le roi déclara avant sa mort"))
}
