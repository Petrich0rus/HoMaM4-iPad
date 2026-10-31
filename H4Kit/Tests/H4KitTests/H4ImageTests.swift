import Foundation
import Testing
@testable import H4Kit

// MARK: - Fixture builder for layers

struct LayerFixture {
    var name = "frame 001"
    var kind: UInt8 = 4
    var rect: (Int32, Int32, Int32, Int32) = (10, 20, 14, 22) // 4×2
    /// BGR palette entries.
    var palette: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (0x30, 0x20, 0x10), (0xFF, 0x00, 0x00)]
    var spans: [(UInt16, UInt16, UInt32)] = [(1, 3, 0), (0, 4, 2)]   // 2 + 4 = 6 pixels
    var indices: [UInt8] = [1, 2, 1, 1, 2, 2]
    var alphaNibbles: [UInt8] = [15, 8, 0, 15, 15, 15]
    var coverage = true

    func bytes() -> Data {
        var d = le16(UInt16(palette.count)) + le16(coverage ? 1 : 0)
        for (b, g, r) in palette { d += Data([b, g, r]) }
        d += str16(name) + Data([kind])
        d += le32(UInt32(bitPattern: rect.0)) + le32(UInt32(bitPattern: rect.1))
        d += le32(UInt32(bitPattern: rect.2)) + le32(UInt32(bitPattern: rect.3))
        for (s, e, o) in spans { d += le16(s) + le16(e) + le32(o) }
        d += Data(indices)
        if kind >= 4 && !spans.isEmpty {
            var packed = [UInt8](repeating: 0, count: (alphaNibbles.count + 1) / 2)
            for (i, a) in alphaNibbles.enumerated() { packed[i / 2] |= (a & 0xF) << (UInt8(i % 2) * 4) }
            d += Data(packed)
            if coverage { d += Data(repeating: 0xAA, count: (indices.count + 0x83) >> 7) }
        }
        return d
    }
}

func group(_ layers: [LayerFixture]) -> Data {
    layers.reduce(le16(UInt16(layers.count))) { $0 + $1.bytes() }
}

func pixel(_ img: H4RGBAImage, _ x: Int, _ y: Int) -> [UInt8] {
    let p = (y * img.width + x) * 4
    return Array(img.pixels[p..<(p + 4)])
}

// MARK: - Layers

@Test func decodesPalettedLayerWithAlpha() throws {
    let g = try H4LayerGroup(data: group([LayerFixture()]))
    let layer = try #require(g.layers.first)
    #expect(layer.name == "frame 001")
    #expect((layer.width, layer.height) == (4, 2))
    let img = layer.rgba()
    // Row 0: span columns 1..<3. Column 0 untouched (transparent).
    #expect(pixel(img, 0, 0) == [0, 0, 0, 0])
    // Palette is stored B,G,R: (0x30,0x20,0x10) must come out as R=0x10, G=0x20, B=0x30.
    #expect(pixel(img, 1, 0) == [0x10, 0x20, 0x30, 255])
    // Second pixel: alpha nibble 8 → 136, low nibble of the first alpha byte holds pixel 0.
    #expect(pixel(img, 2, 0) == [0x00, 0x00, 0xFF, 136])
    // Row 1, column 0 is pixel #2 whose nibble is 0 → fully transparent.
    #expect(pixel(img, 0, 1)[3] == 0)
    #expect(pixel(img, 1, 1) == [0x10, 0x20, 0x30, 255])
    #expect(pixel(img, 3, 1) == [0x00, 0x00, 0xFF, 255])
}

@Test func opaqueKindHasNoAlphaOrSummary() throws {
    var f = LayerFixture()
    f.kind = 1
    // A kind < 4 layer must stop right after its indices; a second layer follows directly.
    var second = LayerFixture()
    second.name = "hot_spot"
    let g = try H4LayerGroup(data: group([f, second]))
    #expect(g.layers.map(\.name) == ["frame 001", "hot_spot"])
    #expect(g.layers[0].alpha == nil)
    #expect(pixel(g.layers[0].rgba(), 0, 1) == [0x10, 0x20, 0x30, 255])
}

@Test func coverageSummaryIsSkippedOnlyWhenFlagged() throws {
    var f = LayerFixture()
    f.coverage = false
    #expect(try H4LayerGroup(data: group([f, LayerFixture()])).layers.count == 2)
}

@Test func emptyLayerIsAllowed() throws {
    var f = LayerFixture()
    f.rect = (0, 7, 0, 7)
    f.spans = []
    f.indices = []
    f.alphaNibbles = []
    let layer = try H4LayerGroup(data: group([f])).layers[0]
    #expect(layer.isEmpty)
    #expect(layer.rgba().pixels.isEmpty)
}

@Test func drawPlacesLayerAtItsRectangle() throws {
    let layer = try H4LayerGroup(data: group([LayerFixture()])).layers[0]
    var canvas = H4RGBAImage(width: 20, height: 25, pixels: [UInt8](repeating: 0, count: 20 * 25 * 4))
    layer.draw(into: &canvas)
    #expect(pixel(canvas, 11, 20) == [0x10, 0x20, 0x30, 255]) // left 10 + column 1, top 20
    #expect(pixel(canvas, 13, 21) == [0x00, 0x00, 0xFF, 255])
}

/// Regression: blending onto a partly transparent canvas used to overflow UInt8 and trap
/// (e.g. alpha 17 drawn twice over (255,255,255)). Checks every alpha the format can
/// produce, every canvas alpha and the extreme colours.
@Test func blendNeverOverflows() {
    for nibble in 1...14 {
        let a = nibble * 17
        for da in 0...255 {
            for s in [UInt8(0), 128, 255] {
                for dc in [UInt8(0), 1, 254, 255] {
                    var d = (dc, dc, dc, UInt8(da))
                    H4Layer.blend(src: (s, s, s), alpha: a, onto: &d)
                    #expect(d.3 >= UInt8(a))
                    // The result lies between the two input colours.
                    #expect(d.0 >= min(s, dc) && d.0 <= max(s, dc))
                }
            }
        }
    }
    // The exact case found by the verifier: same semi-transparent white drawn twice.
    var d: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    H4Layer.blend(src: (255, 255, 255), alpha: 17, onto: &d)
    H4Layer.blend(src: (255, 255, 255), alpha: 17, onto: &d)
    #expect(d.0 == 255 && d.3 == 32)
}

@Test func stackingSemiTransparentLayersDoesNotTrap() throws {
    var f = LayerFixture()
    f.alphaNibbles = [1, 1, 1, 1, 1, 1]
    f.palette = [(0, 0, 0), (255, 255, 255), (255, 255, 255)]
    let layer = try H4LayerGroup(data: group([f])).layers[0]
    var canvas = H4RGBAImage(width: 20, height: 25, pixels: [UInt8](repeating: 0, count: 20 * 25 * 4))
    for _ in 0..<40 { layer.draw(into: &canvas) }
    #expect(pixel(canvas, 11, 20)[0] == 255)
}

@Test func groupBoundsIsUnionOfLayers() throws {
    var b = LayerFixture()
    b.rect = (0, 0, 4, 2)
    let g = try H4LayerGroup(data: group([LayerFixture(), b]))
    #expect(g.bounds! == (0, 0, 14, 22))
}

@Test func rejectsMalformedLayers() throws {
    var spanTooWide = LayerFixture()
    spanTooWide.spans = [(0, 9, 0), (0, 4, 2)]
    #expect(throws: (any Error).self) { try H4LayerGroup(data: group([spanTooWide])) }

    var reversed = LayerFixture()
    reversed.spans = [(3, 1, 0), (0, 4, 2)]
    #expect(throws: (any Error).self) { try H4LayerGroup(data: group([reversed])) }

    var spanPastData = LayerFixture()
    spanPastData.spans = [(0, 4, 5), (0, 1, 2)] // first span needs 4 pixels from offset 5, only 3 exist
    #expect(throws: (any Error).self) { try H4LayerGroup(data: group([spanPastData])) }

    var colorOutsidePalette = LayerFixture()
    colorOutsidePalette.indices = [1, 2, 1, 1, 2, 7]
    #expect(throws: (any Error).self) { try H4LayerGroup(data: group([colorOutsidePalette])) }

    var huge = LayerFixture()
    huge.rect = (0, 0, 4, 2_000_000)
    #expect(throws: (any Error).self) { try H4LayerGroup(data: group([huge])) }

    // A 16384×16384 rectangle with empty spans is only ~131 KB of input but would make
    // rgba() allocate 1 GiB; it must be rejected (game maximum is 1280×1024).
    var wideEmpty = LayerFixture()
    wideEmpty.rect = (0, 0, 16384, 16384)
    wideEmpty.spans = Array(repeating: (0, 0, 0), count: 16384)
    wideEmpty.indices = []
    wideEmpty.alphaNibbles = []
    #expect(throws: (any Error).self) { try H4LayerGroup(data: group([wideEmpty])) }

    let ok = group([LayerFixture()])
    for cut in [1, 5, ok.count / 2, ok.count - 1] {
        #expect(throws: (any Error).self) { try H4LayerGroup(data: ok.prefix(cut)) }
    }
    #expect(throws: (any Error).self) { try H4LayerGroup(data: ok + Data([0])) } // trailing garbage
}

// MARK: - Animation, actor sequence, raw bitmap

@Test func decodesAnimation() throws {
    var a = LayerFixture(); a.name = "frame 001"
    var b = LayerFixture(); b.name = "frame 002"
    var data = group([a, b]) + le16(2) + le16(125) + le32(3) + le32(1) + le32(0) + le32(1)
    data += Data([1, 1]) + le32(33) + le32(UInt32(bitPattern: -5))
    let anim = try H4Animation(data: data)
    #expect(anim.frames.layers.count == 2)
    #expect(anim.frameDurationMilliseconds == 125)
    #expect(anim.frameOrder == [1, 0, 1])
    #expect(anim.extra?.x == 33 && anim.extra?.y == -5)

    let v1 = group([a]) + le16(1) + le16(100) + le32(1) + le32(0)
    #expect(try H4Animation(data: v1).extra == nil)

    let badOrder = group([a]) + le16(1) + le16(100) + le32(1) + le32(4)
    #expect(throws: (any Error).self) { try H4Animation(data: badOrder) }
}

@Test func decodesBothActorSequenceKinds() throws {
    let frames = group([LayerFixture()])
    let tail = le32(UInt32(bitPattern: -361)) + le32(UInt32(bitPattern: -347)) + le16(0)
    let kind2 = try H4ActorSequence(data: le16(2) + le16(2) + frames + tail)
    #expect(kind2.kind == 2 && kind2.originX == -361 && kind2.originY == -347 && kind2.trailer == le16(0))
    let kind3 = try H4ActorSequence(data: le16(2) + le16(3) + le16(1) + le32(0xFFFF_FFFF) + frames + tail)
    #expect(kind3.frames == kind2.frames)
    #expect(throws: (any Error).self) { try H4ActorSequence(data: le16(2) + le16(9) + frames + tail) }
}

@Test func decodesRawBitmap() throws {
    let pixels = Data([0x30, 0x20, 0x10, 1, 2, 3])                // two BGR pixels, 2×1
    let bmp = try H4RawBitmap(data: le32(1) + le32(1) + le32(2) + le32(6) + pixels)
    #expect(bmp.image.pixels == [0x10, 0x20, 0x30, 255, 3, 2, 1, 255])
    #expect(throws: (any Error).self) { try H4RawBitmap(data: le32(1) + le32(1) + le32(2) + le32(7) + pixels) }
}

@Test func pngRoundTripsThroughImageIO() throws {
    let layer = try H4LayerGroup(data: group([LayerFixture()])).layers[0]
    let png = try layer.rgba().pngData()
    #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
}

/// Real game files, when H4_DATA_DIR points at the GOG "Data" folder.
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realGameImages() throws {
    let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: ProcessInfo.processInfo.environment["H4_DATA_DIR"]!))
    let cancel = try H4LayerGroup(data: store.data(for: "layers.button.cancel.h4d"))
    #expect(cancel.layers.map(\.name) == ["Disabled", "Highlighted", "Pressed", "Released"])
    #expect(cancel.layers.allSatisfy { ($0.width, $0.height) == (76, 44) })

    let devil = try H4ActorSequence(data: store.data(for: "actor_sequence.archdevil.walk.e.h4d"))
    #expect(devil.frames.layers.count == 16)
    #expect((devil.originX, devil.originY) == (-361, -347))

    let menu = try H4RawBitmap(data: store.data(for: "bitmap_raw.menu.main.0800.h4d"))
    #expect((menu.image.width, menu.image.height) == (800, 600))
    // First file pixel is B,G,R = 7C 56 12 → R=0x12, G=0x56, B=0x7C.
    #expect(Array(menu.image.pixels[0..<4]) == [0x12, 0x56, 0x7C, 255])
}
