import Foundation

/// Bounds-checked little-endian reader over a `Data` buffer.
/// Every read throws instead of trapping, because archive bytes are untrusted input.
struct ByteReader {
    let data: Data
    private(set) var offset: Int
    /// Nesting of recursive records (script nodes, armies, heroes); see `enter()`.
    private var depth = 0
    /// Deepest nesting accepted. Shipped data stays well below 20; the cap only protects the stack.
    static let maxDepth = 64

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }

    mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= data.count else {
            throw H4Error.truncated(at: newOffset, needed: 0)
        }
        offset = newOffset
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else {
            throw H4Error.truncated(at: offset, needed: count)
        }
        let start = data.startIndex + offset
        offset += count
        return data[start..<(start + count)]
    }

    mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw H4Error.truncated(at: offset, needed: 1) }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func i8() throws -> Int8 { Int8(bitPattern: try u8()) }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    /// Enters one level of a recursive record; pair with `leave()`.
    mutating func enter() throws {
        guard depth < Self.maxDepth else { throw H4Error.malformed("records nested deeper than \(Self.maxDepth) at body offset \(offset)") }
        depth += 1
    }
    mutating func leave() { depth -= 1 }

    /// Throws `H4Error.malformed("<what> at body offset N")` unless `ok`.
    func require(_ ok: Bool, _ what: @autoclosure () -> String) throws {
        guard ok else { throw H4Error.malformed("\(what()) at body offset \(offset)") }
    }

    mutating func i32() throws -> Int32 {
        Int32(bitPattern: try u32())
    }

    mutating func u16() throws -> UInt16 {
        let b = try bytes(2)
        return b.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) }
    }

    mutating func u32() throws -> UInt32 {
        let b = try bytes(4)
        return b.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }

    /// A string prefixed by its UInt16 byte length. HoMM4 stores Windows-1252 text.
    mutating func string16() throws -> String {
        let length = Int(try u16())
        let raw = try bytes(length)
        return String(data: raw, encoding: .windowsCP1252) ?? String(decoding: raw, as: UTF8.self)
    }
}
