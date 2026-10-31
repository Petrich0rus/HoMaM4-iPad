import Foundation
import Testing
@testable import H4Kit

// MARK: - Fixture helpers

func i32le(_ v: Int) -> Data { le32(UInt32(bitPattern: Int32(v))) }

/// Sprite block as read by 0x749b20 for a given inner version.
func spriteBytes(version: UInt16, name: String = "obj") -> Data {
    var d = le16(version)
    if version > 2 { d += le16(1) + le16(0xFFFF) + le16(0xFFFF) }
    d += group([LayerFixture()]) + i32le(-97) + i32le(-31)
    if version == 1 { d += str16(name) }
    return d
}

// MARK: - Fonts

func fontBytes(first: UInt8 = 32, glyphs: [(Int, Int, Int, Int, [UInt8])]) -> Data {
    var d = le16(1) + Data([first, 12, 10, 9, UInt8(glyphs.count)])
    for (w, h, l, r, px) in glyphs { d += i32le(w) + i32le(h) + i32le(l) + i32le(r) + Data(px) }
    return d
}

@Test func decodesFontAndAdvance() throws {
    let font = try H4Font(data: fontBytes(glyphs: [(1, 2, 0, 7, [0, 0]), (2, 2, 1, -1, [0xF0, 0x0F, 0x8F, 0x00])]))
    #expect(font.glyphs.count == 2 && font.height == 12)
    #expect(font.glyph(for: 32)?.advance == 8)              // the space: 0 + 1 + 7
    #expect(font.glyph(for: 33)?.advance == 2)
    #expect(font.glyph(for: 31) == nil && font.glyph(for: 34) == nil)
    let img = font.render(font.glyph(for: 33)!, color: (200, 100, 50))
    #expect(pixel(img, 0, 0) == [200, 100, 50, 255])          // high nibble 15 = letter
    #expect(pixel(img, 1, 0) == [0, 0, 0, 255])               // low nibble 15 = shadow
    #expect(pixel(img, 0, 1)[3] == 255)                       // letter 8/15 over full shadow
    #expect(pixel(img, 1, 1) == [0, 0, 0, 0])
    // Game spacing: no leading space before the first glyph, no trailing space after the last.
    // " " at x 0 (1 px, then 7) → "!" at 0 + 1 + 7 + 1 = 9, 2 px wide → 11.
    let line = font.render(text: " !")
    #expect(line.width == 11 && line.height == 12)
    // Characters the font lacks use its first glyph instead of being dropped (as the game does).
    #expect(font.render(text: "Z").width == 1)
}

/// Regression: absurd spacing in a modified font made render(text:) allocate gigabytes.
@Test func fontSpacingIsBoundedAndRenderWidthCapped() throws {
    #expect(throws: (any Error).self) {
        try H4Font(data: fontBytes(first: 65, glyphs: [(1, 1, 0, 0x7FFF_FFFF, [0xF0])]))
    }
    #expect(throws: (any Error).self) {
        try H4Font(data: fontBytes(first: 65, glyphs: [(1, 1, -300, 0, [0xF0])]))
    }
    // Largest accepted spacing and a long text: width stays capped.
    let wide = try H4Font(data: fontBytes(first: 65, glyphs: [(256, 1, 0, 256, [UInt8](repeating: 0xF0, count: 256))]))
    #expect(wide.render(text: String(repeating: "A", count: 10_000)).width <= H4Font.maxRenderWidth)
    #expect(wide.render(text: "").width == 1)
}

@Test func versionZeroFontPixelsAreRemapped() throws {
    var data = fontBytes(glyphs: [(3, 1, 0, 0, [0, 1, 2])])
    data[0] = 0
    let font = try H4Font(data: data)
    #expect(font.glyphs[0].pixels == Data([0x00, 0x0F, 0xF0]))
}

@Test func rejectsMalformedFonts() {
    #expect(throws: (any Error).self) { try H4Font(data: fontBytes(glyphs: [(1, 1, 0, 0, [])])) }      // missing pixel
    #expect(throws: (any Error).self) { try H4Font(data: fontBytes(glyphs: [(9999, 1, 0, 0, [])])) }   // huge glyph
    #expect(throws: (any Error).self) { try H4Font(data: fontBytes(glyphs: [(1, 1, 0, 0, [0, 0])])) }  // trailing byte
    #expect(throws: (any Error).self) { try H4Font(data: le16(0x0920) + Data([8, 7, 0])) }             // legacy header
}

// MARK: - Terrain

/// Terrain with every tile empty except tile 0, column 0 (1 px) and column 31 (31 px, with a gap).
func terrainBytes(corruptColumn31: Bool = false) -> Data {
    var d = Data()
    for t in 0..<100 {
        var body = Data(), offsets: [Int] = []
        for k in 0..<64 {
            offsets.append(body.count)
            let h = H4TerrainTexture.columnHeight(k)
            if t == 0 && k == 0 {
                body += Data([0, 1, 2])                      // gap 0, one pixel of colour 2
            } else if t == 0 && k == 31 {
                body += Data([3, corruptColumn31 ? 29 : 28]) + Data(repeating: 1, count: 28)  // gap 3 + 28 px = 31
            } else {
                body += Data([UInt8(h)])                     // fully transparent column
            }
        }
        d += le32(UInt32(body.count)) + body
        for o in offsets { d += le32(UInt32(o)) }
    }
    d += le32(256)
    for i in 0..<256 { d += Data([UInt8(i), 0x40, 0x80]) }   // B, G, R
    return d
}

@Test func decodesTerrainTiles() throws {
    let texture = try H4TerrainTexture(data: terrainBytes())
    #expect(texture.tiles.count == 100)
    let img = texture.image(ofTile: 0)
    #expect((img.width, img.height) == (64, 32))
    // Column 0 is 1 px tall, centred at row 15; palette stored B,G,R → (R,G,B) = (0x80,0x40,2).
    #expect(pixel(img, 0, 15) == [0x80, 0x40, 2, 255])
    #expect(pixel(img, 0, 14)[3] == 0)
    // Column 31 is 31 px tall starting at row 0: rows 0–2 are the gap, row 3 the first pixel.
    #expect(pixel(img, 31, 2)[3] == 0)
    #expect(pixel(img, 31, 3) == [0x80, 0x40, 1, 255])
    #expect(texture.image(ofTile: 5).pixels.allSatisfy { $0 == 0 })
}

@Test func rejectsMalformedTerrain() {
    #expect(throws: (any Error).self) { try H4TerrainTexture(data: terrainBytes(corruptColumn31: true)) }
    let ok = terrainBytes()
    #expect(throws: (any Error).self) { try H4TerrainTexture(data: ok.prefix(ok.count - 1)) }
    #expect(throws: (any Error).self) { try H4TerrainTexture(data: ok + Data([0])) }
}

// MARK: - Adventure objects

func advObjectBytes(version: UInt16, imageKind: UInt8, imageVersion: UInt16 = 2, sprite: UInt16 = 3) -> Data {
    let w = 3, h = 2
    var d = le16(version) + Data([10])
    let edge: UInt16 = version >= 3 ? 1 : 0
    if version >= 3 { d += le16(edge) }
    d += le16(UInt16(w)) + le16(UInt16(h))
    func bits(_ n: Int, _ fill: UInt8 = 0) -> Data { Data(repeating: fill, count: (n + 7) / 8) }
    d += Data([0b0011_1111])                                  // 6 blocked cells
    if edge < 1 { d += bits(w * h) } else { d += bits((h + 1) * w) + bits((w + 1) * h) }
    if version > 5 { d += bits(2 * (h + 1) * w) + bits(2 * (w + 1) * h) + Data(repeating: 0, count: (w + 1) * (h + 1)) }
    if version > 1 { d += le16(0) + le16(80) + str16("sphinx") + le16(0) + str16("") + le16(0) + str16("") }
    if version >= 4 { d += Data([1]) }
    if version >= 5 { d += Data([1]) + le32(5) + le32(6) }
    d += Data([imageKind]) + le16(imageVersion)
    if imageVersion != 0 { d += le16(1) + spriteBytes(version: sprite) } else { d += spriteBytes(version: 0).dropFirst(2) }
    if imageKind == 0 { d += le32(3) + le16(0xFFFD) + le16(0xFFFC) + le16(2) }
    return d
}

@Test func decodesAdventureObjectVariants() throws {
    let sphinx = try H4AdventureObject(data: advObjectBytes(version: 6, imageKind: 0))
    #expect((sphinx.width, sphinx.height) == (3, 2))
    #expect(sphinx.blockedCells == [true, true, true, true, true, true])
    #expect(sphinx.classification.first?.name == "sphinx" && sphinx.classification.first?.id == 80)
    #expect(sphinx.sprite.extra == [1, 0xFFFF, 0xFFFF] && sphinx.sprite.originX == -97)
    #expect(sphinx.columnDepths == [-3, -4, 2])

    let animal = try H4AdventureObject(data: advObjectBytes(version: 6, imageKind: 1))
    #expect(animal.columnDepths.isEmpty && animal.sprite.frames.layers.count == 1)

    for (version, sprite) in [(5, UInt16(2)), (4, 2), (3, 1), (2, 2), (1, 2)] {
        let o = try H4AdventureObject(data: advObjectBytes(version: UInt16(version), imageKind: 0, sprite: sprite))
        #expect(o.version == UInt16(version))
        if sprite == 1 { #expect(o.sprite.name == "obj") }
    }
    #expect(try H4AdventureObject(data: advObjectBytes(version: 6, imageKind: 0, imageVersion: 0)).sprite.version == 0)
}

@Test func rejectsMalformedAdventureObjects() {
    var future = advObjectBytes(version: 6, imageKind: 0)
    future[0] = 7
    #expect(throws: (any Error).self) { try H4AdventureObject(data: future) }
    var versionZero = advObjectBytes(version: 1, imageKind: 0)
    versionZero[0] = 0
    #expect(throws: H4Error.malformed("adventure object version 0")) { try H4AdventureObject(data: versionZero) }
    var badKind = advObjectBytes(version: 1, imageKind: 0)
    // Version 1: u16 version, u8 type, u16 w, u16 h, 1 byte of cells, 1 byte of cells → kind at 9.
    #expect(badKind[9] == 0)
    badKind[9] = 5
    #expect(throws: H4Error.malformed("adventure object image kind 5")) { try H4AdventureObject(data: badKind) }
    #expect(throws: (any Error).self) { try H4AdventureObject(data: badKind) }
    let ok = advObjectBytes(version: 6, imageKind: 0)
    #expect(throws: (any Error).self) { try H4AdventureObject(data: ok + Data([0])) }
    #expect(throws: (any Error).self) { try H4AdventureObject(data: ok.prefix(ok.count - 1)) }
}

// MARK: - Combat objects

func combatObjectBytes(version: UInt16, sprite: UInt16 = 2, fps: UInt8 = 10) -> Data {
    var d = le16(version) + (version < 2 ? Data([3]) : Data([3, 4])) + Data([50, fps, 0])
    if version >= 1 { d += Data([1, 1, 0, 0, 0]) + le16(2) + str16("black_rock") }
    return d + spriteBytes(version: sprite)
}

@Test func decodesCombatObjects() throws {
    let rock = try H4CombatObject(data: combatObjectBytes(version: 2))
    #expect((rock.width, rock.height, rock.elevation, rock.framesPerSecond) == (3, 4, 50, 10))
    #expect(rock.typeName == "black_rock" && rock.typeID == 2 && rock.properties == [1, 1, 0, 0, 0])
    let old = try H4CombatObject(data: combatObjectBytes(version: 0))
    #expect((old.width, old.height) == (3, 3) && old.typeName == nil)
    #expect(try H4CombatObject(data: combatObjectBytes(version: 2, sprite: 3)).sprite.extra.count == 3)
    #expect(try H4CombatObject(data: combatObjectBytes(version: 2, sprite: 1)).sprite.name == "obj")
}

@Test func rejectsMalformedCombatObjects() {
    #expect(throws: (any Error).self) { try H4CombatObject(data: combatObjectBytes(version: 3)) }
    #expect(throws: (any Error).self) { try H4CombatObject(data: combatObjectBytes(version: 2, fps: 0)) }
    let ok = combatObjectBytes(version: 2)
    #expect(throws: (any Error).self) { try H4CombatObject(data: ok + Data([0])) }
    #expect(throws: (any Error).self) { try H4CombatObject(data: ok.prefix(ok.count - 1)) }
}

// MARK: - Real data

@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realGameWorldResources() throws {
    let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: ProcessInfo.processInfo.environment["H4_DATA_DIR"]!))

    let sphinx = try H4AdventureObject(data: store.data(for: "adv_object.power ups.Sphinx.h4d"))
    #expect((sphinx.width, sphinx.height, sphinx.objectType) == (3, 2, 10))
    #expect(sphinx.classification.first?.name == "sphinx")
    #expect(sphinx.sprite.frames.layers.map(\.name) == ["frame 001", "shadow 001"])
    #expect((sphinx.sprite.originX, sphinx.sprite.originY) == (-97, -31))
    #expect(sphinx.columnDepths == [-3, -4, -4, -3, -2])

    let rock = try H4CombatObject(data: store.data(for: "combat_object.Obstacles.Rocks.Lava.05.h4d"))
    #expect((rock.width, rock.height, rock.framesPerSecond) == (3, 4, 10))
    #expect(rock.typeName == "black_rock")

    let grass = try H4TerrainTexture(data: store.data(for: "terrain.grass.2.1.h4d"))
    let tile = grass.image(ofTile: 44)
    // A full grass tile: centre pixel opaque and green-dominant, corners transparent.
    let centre = pixel(tile, 32, 16)
    #expect(centre[3] == 255 && centre[1] > centre[0] && centre[1] > centre[2])
    #expect(pixel(tile, 0, 0)[3] == 0 && pixel(tile, 63, 31)[3] == 0)

    let font = try H4Font(data: store.data(for: "font.Prose_Antique.36.h4d"))
    #expect(font.glyphs.count == 225 && font.firstCharacter == 31)
    #expect(font.glyph(for: 32)?.advance == 8)
    #expect(font.render(text: "Héros IV").width > 0)
}
