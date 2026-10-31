import Compression
import Foundation

/// Minimal gzip (RFC 1952) decoder built on Apple's Compression framework,
/// which is available on both iPadOS and macOS. `COMPRESSION_ZLIB` there means raw DEFLATE.
enum Gzip {
    static func decompress(_ input: Data, expectedSize: Int, name: String) throws -> Data {
        var r = ByteReader(input)
        guard input.count >= 18, try r.bytes(2) == Data([0x1F, 0x8B]) else {
            throw H4Error.gzip(name: name, reason: "missing gzip signature")
        }
        let method = try r.bytes(1).first!
        guard method == 8 else { throw H4Error.gzip(name: name, reason: "unsupported method \(method)") }
        let flags = try r.bytes(1).first!
        _ = try r.bytes(6) // mtime, xfl, os
        if flags & 0x04 != 0 { _ = try r.bytes(Int(try r.u16())) } // FEXTRA
        if flags & 0x08 != 0 { try skipCString(&r) } // FNAME
        if flags & 0x10 != 0 { try skipCString(&r) } // FCOMMENT
        if flags & 0x02 != 0 { _ = try r.bytes(2) } // FHCRC

        let deflateStart = r.offset
        let deflateEnd = input.count - 8
        guard deflateEnd >= deflateStart else { throw H4Error.gzip(name: name, reason: "truncated stream") }

        var trailer = ByteReader(input, offset: deflateEnd)
        let storedCRC = try trailer.u32()
        let storedSize = Int(try trailer.u32())
        guard storedSize == expectedSize & 0xFFFF_FFFF else {
            throw H4Error.sizeMismatch(name: name, expected: expectedSize, actual: storedSize)
        }

        let output = try inflate(input[(input.startIndex + deflateStart)..<(input.startIndex + deflateEnd)],
                                 capacity: expectedSize, name: name)
        guard output.count == expectedSize else {
            throw H4Error.sizeMismatch(name: name, expected: expectedSize, actual: output.count)
        }
        guard CRC32.checksum(output) == storedCRC else {
            throw H4Error.gzip(name: name, reason: "CRC32 mismatch")
        }
        return output
    }

    private static func skipCString(_ r: inout ByteReader) throws {
        while try r.bytes(1).first! != 0 {}
    }

    private static func inflate(_ deflated: Data, capacity: Int, name: String) throws -> Data {
        // One spare byte: a stream that inflates past the declared size fills it and is rejected
        // by the caller's size check instead of being silently truncated.
        let bufferSize = capacity + 1
        var output = Data(count: bufferSize)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            deflated.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, bufferSize,
                    srcBase, deflated.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 || capacity == 0 else { throw H4Error.gzip(name: name, reason: "inflate failed") }
        output.count = written
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buf in
            for byte in buf { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
