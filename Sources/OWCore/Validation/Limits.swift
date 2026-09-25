import Foundation

/// Hard caps applied to all untrusted input. Central so they can be audited in one place.
public enum Limits {
    public static let maxJSONBytes = 8 * 1024 * 1024
    public static let maxJSONDepth = 64
    public static let maxPackageEntries = 65_536
    public static let maxPackageNameBytes = 1024
    public static let maxPackageMagicBytes = 32
    public static let maxTextureDimension = 16_384
    public static let maxTextureImages = 4_096
    public static let maxTextureMipmaps = 16
    public static let maxDecompressedBytes = 512 * 1024 * 1024
    public static let maxSceneObjects = 4_096
    public static let maxParticles = 20_000
    public static let maxProperties = 512
}

public enum JSONGuardError: Error, Equatable, Sendable {
    case tooLarge(Int)
    case tooDeep(Int)
    case notAnObject
    case malformed(String)
}

/// Checks size and nesting depth before handing bytes to a JSON parser.
public enum JSONGuard {
    public static func check(
        _ data: Data,
        maxBytes: Int = Limits.maxJSONBytes,
        maxDepth: Int = Limits.maxJSONDepth
    ) throws(JSONGuardError) {
        guard data.count <= maxBytes else { throw .tooLarge(data.count) }
        let depth = maximumDepth(of: data)
        guard depth <= maxDepth else { throw .tooDeep(depth) }
    }

    /// Guards and parses a top-level JSON object.
    public static func object(from data: Data) throws(JSONGuardError) -> [String: Any] {
        try check(data)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw .malformed(error.localizedDescription)
        }
        guard let object = parsed as? [String: Any] else { throw .notAnObject }
        return object
    }

    /// Bracket depth, ignoring brackets inside string literals.
    static func maximumDepth(of data: Data) -> Int {
        var depth = 0
        var maximum = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                maximum = max(maximum, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth = max(depth - 1, 0)
            default: break
            }
        }
        return maximum
    }
}
