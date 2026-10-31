import Foundation

public enum H4Error: Error, CustomStringConvertible, Equatable {
    case badMagic
    case truncated(at: Int, needed: Int)
    case entryOutOfBounds(name: String)
    case unknownStorage(name: String, code: UInt32)
    case gzip(name: String, reason: String)
    case sizeMismatch(name: String, expected: Int, actual: Int)
    case notFound(name: String)
    case aliasCycle(name: String)
    case unsafeName(String)
    case tooLarge(name: String, size: Int)
    case malformed(String)

    public var description: String {
        switch self {
        case .badMagic: return "Not an H4R archive (missing 'H4R\\x05' signature)"
        case let .truncated(at, needed): return "Archive truncated: needed \(needed) bytes at offset \(at)"
        case let .entryOutOfBounds(name): return "Entry '\(name)' points outside the archive"
        case let .unknownStorage(name, code): return "Entry '\(name)' uses unknown storage code \(code)"
        case let .gzip(name, reason): return "Entry '\(name)': gzip error: \(reason)"
        case let .sizeMismatch(name, expected, actual): return "Entry '\(name)': expected \(expected) bytes, got \(actual)"
        case let .notFound(name): return "Resource '\(name)' not found"
        case let .aliasCycle(name): return "Alias cycle while resolving '\(name)'"
        case let .unsafeName(name): return "Refusing unsafe resource name '\(name)'"
        case let .tooLarge(name, size): return "Entry '\(name)' declares \(size) bytes, above the safety limit"
        case let .malformed(reason): return "Malformed resource: \(reason)"
        }
    }
}
