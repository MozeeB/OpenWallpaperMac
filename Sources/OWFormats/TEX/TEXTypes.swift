import Foundation

public enum TEXError: Error, Equatable, Sendable {
    case invalidMagic(expected: String, found: String)
    case unsupportedContainer(String)
    case unsupportedFormat(Int32)
    case invalidDimensions(width: Int, height: Int)
    case tooManyImages(Int)
    case tooManyMipmaps(Int)
    case decompressionFailed(expected: Int, actual: Int)
    case payloadTooSmall(expected: Int, actual: Int)
    case truncated(BinaryReaderError)
    case imageDecodeFailed
    case textureTooLarge(limit: Int)
    case noImages
}

/// Raw pixel encodings found in textures.
public enum TEXFormat: Int32, Sendable, CaseIterable {
    case rgba8888 = 0
    case dxt5 = 4
    case dxt3 = 6
    case dxt1 = 7
    case rg88 = 8
    case r8 = 9

    /// Bytes required for a `width`×`height` image in this format.
    public func byteCount(width: Int, height: Int) -> Int {
        let blocks = ((width + 3) / 4) * ((height + 3) / 4)
        switch self {
        case .rgba8888: return width * height * 4
        case .rg88: return width * height * 2
        case .r8: return width * height
        case .dxt1: return blocks * 8
        case .dxt3, .dxt5: return blocks * 16
        }
    }

    public var isBlockCompressed: Bool {
        switch self {
        case .dxt1, .dxt3, .dxt5: return true
        default: return false
        }
    }
}

public struct TEXFlags: OptionSet, Sendable, Equatable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let noInterpolation = TEXFlags(rawValue: 1)
    public static let clampUVs = TEXFlags(rawValue: 2)
    public static let isGif = TEXFlags(rawValue: 4)
    public static let isVideo = TEXFlags(rawValue: 32)
}

public struct TEXHeader: Equatable, Sendable {
    public let format: Int32
    public let flags: TEXFlags
    /// Power-of-two storage size.
    public let textureWidth: Int
    public let textureHeight: Int
    /// Visible image size inside the storage.
    public let imageWidth: Int
    public let imageHeight: Int
}

/// How mipmap bytes should be interpreted.
public enum TEXPayload: Equatable, Sendable {
    case raw(TEXFormat)
    /// A complete encoded image file (PNG, JPEG…) identified by its FreeImage format id.
    case encodedImage(Int32)
    case mp4
}

public struct TEXMipmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Decompressed bytes.
    public let data: Data
}

public struct TEXImage: Equatable, Sendable {
    public let mipmaps: [TEXMipmap]
}

/// One frame of an animated (GIF-style) texture: a sub-rectangle of an image.
public struct TEXFrame: Equatable, Sendable {
    public let imageIndex: Int
    public let frameTime: Float
    public let x: Float
    public let y: Float
    public let width: Float
    public let height: Float
}

/// A fully parsed texture.
public struct TEXTexture: Equatable, Sendable {
    public let header: TEXHeader
    public let containerVersion: Int
    public let payload: TEXPayload
    public let images: [TEXImage]
    public let frames: [TEXFrame]

    public var isAnimated: Bool { !frames.isEmpty }

    /// Largest mipmap of the first image.
    public var primaryMipmap: TEXMipmap? { images.first?.mipmaps.first }
}
