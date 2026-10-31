import Compression
import Foundation
import Testing
@testable import H4Kit

// MARK: - Fixture builder

struct FixtureEntry {
    var name: String
    var payload: Data = Data()
    var gzip = true
    var alias: String? = nil
    var path = ""
}

func gzipped(_ data: Data) -> Data {
    var deflated = Data(count: data.count + 1024)
    let n = deflated.withUnsafeMutableBytes { dst in
        data.withUnsafeBytes { src in
            compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, data.count + 1024,
                                      src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    deflated.count = n
    var out = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 0x0B])
    out += deflated
    out += le32(CRC32.checksum(data)) + le32(UInt32(data.count))
    return out
}

func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
func str16(_ s: String) -> Data { le16(UInt16(s.utf8.count)) + Data(s.utf8) }

/// Builds an archive with the payloads first and the directory after them
/// (real archives put it at offset 8, or between payloads in text.h4r; the reader only follows the offset).
func buildArchive(_ entries: [FixtureEntry]) -> Data {
    var body = Data("H4R".utf8) + Data([5]) + le32(0)
    var records = Data()
    for e in entries {
        let stored = e.alias == nil ? (e.gzip ? gzipped(e.payload) : e.payload) : Data()
        let offset = e.alias == nil ? UInt32(body.count) : 0
        body += stored
        records += le32(offset) + le32(UInt32(stored.count)) + le32(UInt32(e.payload.count)) + le32(1_000_000_000)
        records += str16(e.name) + str16(e.path) + str16(e.alias ?? "") + le32(e.gzip ? 3 : 1)
    }
    let dirOffset = UInt32(body.count)
    body.replaceSubrange(4..<8, with: le32(dirOffset))
    return body + le32(UInt32(entries.count)) + records
}

// MARK: - Tests

@Test func parsesGzipRawAndAliases() throws {
    let text = Data(String(repeating: "Heroes IV ", count: 500).utf8)
    let data = buildArchive([
        .init(name: "strings.test.h4d", payload: text, path: "C:\\Heroes4\\"),
        .init(name: "bink.intro.h4d", payload: Data([1, 2, 3, 4]), gzip: false),
        .init(name: "strings.link.h4d", alias: "strings.test.h4d"),
    ])
    let archive = try H4RArchive(data: data)
    #expect(archive.entries.count == 3)
    #expect(archive.entries[0].sourcePath == "C:\\Heroes4\\")
    #expect(archive.entries[0].resourceType == "strings")
    #expect(try archive.payload(of: archive.entries[0]) == text)
    #expect(try archive.payload(of: archive.entries[1]) == Data([1, 2, 3, 4]))
    let store = try H4ResourceStore(archives: [archive])
    #expect(try store.data(for: "strings.link.h4d") == text)
}

@Test func laterArchiveOverridesEarlier() throws {
    let base = try H4RArchive(data: buildArchive([.init(name: "a.x.h4d", payload: Data("old".utf8))]))
    let patch = try H4RArchive(data: buildArchive([.init(name: "a.x.h4d", payload: Data("new".utf8))]))
    let store = try H4ResourceStore(archives: [base, patch])
    #expect(try store.data(for: "a.x.h4d") == Data("new".utf8))
}

@Test func aliasCanCrossArchives() throws {
    let a = try H4RArchive(data: buildArchive([.init(name: "a.link.h4d", alias: "b.real.h4d")]))
    let b = try H4RArchive(data: buildArchive([.init(name: "b.real.h4d", payload: Data("ok".utf8))]))
    #expect(try H4ResourceStore(archives: [a, b]).data(for: "a.link.h4d") == Data("ok".utf8))
}

@Test func lookupIgnoresCase() throws {
    let a = try H4RArchive(data: buildArchive([
        .init(name: "adv_actor.Arch Devil.h4d", alias: "adv_actor.Archdevil.h4d"),
        .init(name: "adv_actor.archdevil.h4d", payload: Data("devil".utf8)),
    ]))
    let store = try H4ResourceStore(archives: [a])
    #expect(try store.data(for: "adv_actor.Arch Devil.h4d") == Data("devil".utf8))
    #expect(try store.data(for: "ADV_ACTOR.ARCHDEVIL.H4D") == Data("devil".utf8))
}

@Test func detectsAliasCycle() throws {
    let a = try H4RArchive(data: buildArchive([
        .init(name: "a.one.h4d", alias: "a.two.h4d"), .init(name: "a.two.h4d", alias: "a.one.h4d"),
    ]))
    #expect(throws: H4Error.aliasCycle(name: "a.one.h4d")) { try H4ResourceStore(archives: [a]).data(for: "a.one.h4d") }
}

@Test func rejectsMalformedInput() throws {
    #expect(throws: H4Error.badMagic) { try H4RArchive(data: Data("NOPE0000".utf8)) }
    var data = buildArchive([.init(name: "a.b.h4d", payload: Data("x".utf8))])
    data = data.prefix(data.count - 3) // cut the directory
    #expect(throws: (any Error).self) { try H4RArchive(data: data) }

    // Entry pointing past the end of the file.
    var bad = buildArchive([.init(name: "a.b.h4d", payload: Data("hello".utf8), gzip: false)])
    let dir = Int(bad.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
    bad.replaceSubrange((dir + 4)..<(dir + 8), with: le32(0xFFFF_0000))
    #expect(throws: H4Error.entryOutOfBounds(name: "a.b.h4d")) { try H4RArchive(data: bad) }

    // Corrupted gzip payload must fail the CRC/inflate check, not return garbage.
    var corrupt = buildArchive([.init(name: "a.c.h4d", payload: Data(repeating: 7, count: 4000))])
    corrupt[20] ^= 0xFF
    let archive = try H4RArchive(data: corrupt)
    #expect(throws: (any Error).self) { try archive.payload(of: archive.entries[0]) }
}

@Test func rejectsGzipThatInflatesPastDeclaredSize() throws {
    let big = Data(repeating: 9, count: 1000)
    var stream = gzipped(big)
    // Rewrite the trailer to claim 10 bytes, with the CRC of the first 10.
    stream.replaceSubrange((stream.count - 8)..<stream.count, with: le32(CRC32.checksum(big.prefix(10))) + le32(10))
    #expect(throws: (any Error).self) { try Gzip.decompress(stream, expectedSize: 10, name: "x") }
}

@Test func extractionSkipsBrokenEntriesAndContinues() throws {
    let a = try H4RArchive(data: buildArchive([
        .init(name: "a.broken.h4d", alias: "a.missing.h4d"),
        .init(name: "a.good.h4d", payload: Data("ok".utf8)),
    ]))
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: out) }
    let report = H4Extraction.extract(store: try H4ResourceStore(archives: [a]), to: out)
    #expect(report.written == 1)
    #expect(report.failures.map(\.name) == ["a.broken.h4d"])
    #expect(try Data(contentsOf: out.appendingPathComponent("a/good.h4d")) == Data("ok".utf8))
}

@Test func extractionPathsAreSafe() throws {
    #expect(try H4Extraction.relativePath(for: "layers.button.cancel.h4d") == "layers/button.cancel.h4d")
    for bad in ["../evil", "a/b", "a\\b", ".hidden", "", "x..y"] {
        #expect(throws: H4Error.unsafeName(bad)) { try H4Extraction.relativePath(for: bad) }
    }
}

/// Runs against the real game files when H4_DATA_DIR points at the GOG "Data" folder.
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realGameData() throws {
    let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["H4_DATA_DIR"]!)
    let store = try H4ResourceStore(dataDirectory: dir)
    #expect(store.archives.count == 9)
    #expect(store.archives.first?.entries.count == 17478)
    let cancel = try store.data(for: "layers.button.cancel.h4d")
    #expect(cancel.count == 0x5CBC)
    // Alias: resolves to its target's bytes (the alias record's own size field is not used).
    #expect(try store.data(for: "layers.new_game.h4d") == store.data(for: "layers.dialog.new_game.h4d"))
}
