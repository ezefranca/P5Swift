import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum P5RasterColorSpace {
    static func preferred(
        makeSRGB: () -> CGColorSpace? = { CGColorSpace(name: CGColorSpace.sRGB) }
    ) -> CGColorSpace {
        makeSRGB() ?? CGColorSpaceCreateDeviceRGB()
    }
}

/// The interpretation of image destination coordinates.
public enum P5ImageMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// The first pair is the top-left corner and the next pair is size.
    case corner
    /// The two coordinate pairs are opposite corners.
    case corners
    /// The first pair is the center and the next pair is full size.
    case center
}

/// Failures produced by native image decoding, encoding, and bitmap allocation.
public enum P5ImageError: Error, Sendable, Hashable, LocalizedError {
    /// ImageIO could not decode the supplied bytes.
    case decodingFailed
    /// ImageIO could not encode the requested representation.
    case encodingFailed(P5ImageFormat)
    /// Core Graphics could not allocate a bitmap of the requested size.
    case bitmapAllocationFailed
    /// A named image was absent from the selected bundle.
    case resourceNotFound(String)
    /// A remote server returned a status outside the successful `200...299` range.
    case invalidHTTPStatus(Int)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .decodingFailed:
            "The supplied data is not a supported image."
        case .encodingFailed(let format):
            "The image could not be encoded as \(format.rawValue.uppercased())."
        case .bitmapAllocationFailed:
            "Core Graphics could not allocate the requested bitmap."
        case .resourceNotFound(let name):
            "The image resource '\(name)' was not found in the selected bundle."
        case .invalidHTTPStatus(let status):
            "The image request failed with HTTP status \(status)."
        }
    }
}

/// A native image representation supported by ImageIO export.
public enum P5ImageFormat: String, Sendable, Hashable, Codable, CaseIterable {
    /// Portable Network Graphics with lossless alpha.
    case png
    /// Joint Photographic Experts Group lossy encoding.
    case jpeg
    /// High Efficiency Image File Format using Apple's HEIC encoder.
    case heif

    var uniformType: UTType {
        switch self {
        case .png:
            .png
        case .jpeg:
            .jpeg
        case .heif:
            .heic
        }
    }
}

/// Straight-alpha, row-major RGBA8 pixels with explicit raster density.
public struct P5PixelBuffer: Sendable, Hashable, Codable {
    /// Number of raster columns.
    public let width: Int
    /// Number of raster rows.
    public let height: Int
    /// Raster pixels represented by one logical canvas point.
    public let pixelDensity: CGFloat
    /// Straight-alpha bytes ordered red, green, blue, alpha from top-left to bottom-right.
    public private(set) var bytes: [UInt8]

    /// Creates a validated RGBA8 buffer.
    ///
    /// - Precondition: Dimensions and density are positive, and `bytes` contains
    ///   exactly `width * height * 4` values.
    public init(width: Int, height: Int, pixelDensity: CGFloat = 1, bytes: [UInt8]) {
        precondition(width > 0 && height > 0)
        precondition(pixelDensity.isFinite && pixelDensity > 0)
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        precondition(!pixelOverflow && !byteOverflow && bytes.count == byteCount)
        self.width = width
        self.height = height
        self.pixelDensity = pixelDensity
        self.bytes = bytes
    }

    /// Logical extent represented by the raster.
    public var size: CGSize {
        CGSize(width: CGFloat(width) / pixelDensity, height: CGFloat(height) / pixelDensity)
    }

    /// Returns the straight-alpha color at a zero-based raster coordinate.
    public func color(x: Int, y: Int) -> P5Color {
        let offset = byteOffset(x: x, y: y)
        return P5Color(
            red: CGFloat(bytes[offset]) / 255,
            green: CGFloat(bytes[offset + 1]) / 255,
            blue: CGFloat(bytes[offset + 2]) / 255,
            alpha: CGFloat(bytes[offset + 3]) / 255
        )
    }

    /// Replaces one raster coordinate with a straight-alpha color.
    public mutating func setColor(_ color: P5Color, x: Int, y: Int) {
        let offset = byteOffset(x: x, y: y)
        bytes[offset] = Self.byte(color.red)
        bytes[offset + 1] = Self.byte(color.green)
        bytes[offset + 2] = Self.byte(color.blue)
        bytes[offset + 3] = Self.byte(color.alpha)
    }

    /// Decodes and revalidates serialized dimensions and storage.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height),
            pixelDensity: try container.decode(CGFloat.self, forKey: .pixelDensity),
            bytes: try container.decode([UInt8].self, forKey: .bytes)
        )
    }

    private func byteOffset(x: Int, y: Int) -> Int {
        precondition((0..<width).contains(x) && (0..<height).contains(y))
        return ((y * width) + x) * 4
    }

    private static func byte(_ component: CGFloat) -> UInt8 {
        UInt8((component * 255).rounded())
    }
}

/// Immutable Core Graphics image geometry with explicit logical pixel density.
public struct P5Image: @unchecked Sendable {
    /// Immutable native image storage.
    public let cgImage: CGImage
    /// Raster pixels represented by one logical canvas point.
    public let pixelDensity: CGFloat

    /// Creates an image from immutable Core Graphics storage.
    ///
    /// - Precondition: `pixelDensity` is finite and positive.
    public init(cgImage: CGImage, pixelDensity: CGFloat = 1) {
        precondition(pixelDensity.isFinite && pixelDensity > 0)
        self.cgImage = cgImage
        self.pixelDensity = pixelDensity
    }

    /// Creates an image from straight-alpha RGBA8 pixels.
    public init(pixelBuffer: P5PixelBuffer) throws {
        try self.init(pixelBuffer: pixelBuffer) { bytes, width, height in
            Self.makeImage(bytes, width: width, height: height)
        }
    }

    init(
        pixelBuffer: P5PixelBuffer,
        makeImage: ([UInt8], Int, Int) -> CGImage?
    ) throws {
        var premultiplied = pixelBuffer.bytes
        for offset in stride(from: 0, to: premultiplied.count, by: 4) {
            let alpha = UInt16(premultiplied[offset + 3])
            premultiplied[offset] = UInt8((UInt16(premultiplied[offset]) * alpha + 127) / 255)
            premultiplied[offset + 1] = UInt8(
                (UInt16(premultiplied[offset + 1]) * alpha + 127) / 255
            )
            premultiplied[offset + 2] = UInt8(
                (UInt16(premultiplied[offset + 2]) * alpha + 127) / 255
            )
        }
        guard let image = makeImage(premultiplied, pixelBuffer.width, pixelBuffer.height) else {
            throw P5ImageError.bitmapAllocationFailed
        }
        self.init(cgImage: image, pixelDensity: pixelBuffer.pixelDensity)
    }

    /// Number of raster columns.
    public var pixelWidth: Int {
        cgImage.width
    }

    /// Number of raster rows.
    public var pixelHeight: Int {
        cgImage.height
    }

    /// Logical width in canvas points.
    public var width: CGFloat {
        CGFloat(pixelWidth) / pixelDensity
    }

    /// Logical height in canvas points.
    public var height: CGFloat {
        CGFloat(pixelHeight) / pixelDensity
    }

    /// Logical image extent in canvas points.
    public var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// Decodes the first ImageIO frame from bytes.
    public static func decode(_ data: Data, pixelDensity: CGFloat = 1) throws -> P5Image {
        precondition(pixelDensity.isFinite && pixelDensity > 0)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw P5ImageError.decodingFailed
        }
        return P5Image(cgImage: image, pixelDensity: pixelDensity)
    }

    /// Decodes a named image resource from an explicit Foundation bundle.
    public static func loadResource(
        named name: String,
        withExtension extensionName: String? = nil,
        in bundle: Bundle = .main,
        pixelDensity: CGFloat = 1
    ) throws -> P5Image {
        guard let url = bundle.url(forResource: name, withExtension: extensionName) else {
            throw P5ImageError.resourceNotFound(name)
        }
        return try decode(Data(contentsOf: url), pixelDensity: pixelDensity)
    }

    /// Loads an image from a local file or remote HTTP(S) URL.
    ///
    /// Cancellation is checked after I/O and before ImageIO decoding.
    public static func load(
        from url: URL,
        pixelDensity: CGFloat = 1,
        session: URLSession = .shared
    ) async throws -> P5Image {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (remoteData, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
                !(200...299).contains(httpResponse.statusCode)
            {
                throw P5ImageError.invalidHTTPStatus(httpResponse.statusCode)
            }
            data = remoteData
        }
        try Task.checkCancellation()
        return try decode(data, pixelDensity: pixelDensity)
    }

    /// Returns straight-alpha, top-left-origin RGBA8 pixels.
    public func pixelBuffer() throws -> P5PixelBuffer {
        try pixelBuffer(makeContext: Self.makeBitmapContext)
    }

    func pixelBuffer(
        makeContext: (UnsafeMutableRawPointer?, Int, Int, Int) -> CGContext?
    ) throws -> P5PixelBuffer {
        let bytesPerRow = pixelWidth * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard
                let context = makeContext(
                    storage.baseAddress,
                    pixelWidth,
                    pixelHeight,
                    bytesPerRow
                )
            else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard rendered else {
            throw P5ImageError.bitmapAllocationFailed
        }
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = UInt16(bytes[offset + 3])
            if alpha == 0 {
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
            } else if alpha < 255 {
                bytes[offset] = Self.unpremultiply(bytes[offset], alpha: alpha)
                bytes[offset + 1] = Self.unpremultiply(bytes[offset + 1], alpha: alpha)
                bytes[offset + 2] = Self.unpremultiply(bytes[offset + 2], alpha: alpha)
            }
        }
        return P5PixelBuffer(
            width: pixelWidth,
            height: pixelHeight,
            pixelDensity: pixelDensity,
            bytes: bytes
        )
    }

    /// Encodes this image through ImageIO.
    ///
    /// - Parameters:
    ///   - format: Destination representation.
    ///   - quality: Lossy compression quality in `0...1`; ignored by lossless encoders.
    /// - Returns: Complete encoded image bytes.
    /// - Throws: ``P5ImageError/encodingFailed(_:)`` when ImageIO cannot create
    ///   or finalize the requested destination.
    public func encoded(as format: P5ImageFormat, quality: CGFloat = 0.9) throws -> Data {
        try encoded(
            as: format,
            quality: quality,
            createDestination: CGImageDestinationCreateWithData,
            finalize: CGImageDestinationFinalize
        )
    }

    func encoded(
        as format: P5ImageFormat,
        quality: CGFloat,
        createDestination: (CFMutableData, CFString, Int, CFDictionary?) -> CGImageDestination?,
        finalize: (CGImageDestination) -> Bool
    ) throws -> Data {
        precondition(quality.isFinite && (0...1).contains(quality))
        let data = NSMutableData()
        guard
            let destination = createDestination(
                data,
                format.uniformType.identifier as CFString,
                1,
                nil
            )
        else {
            throw P5ImageError.encodingFailed(format)
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard finalize(destination) else {
            throw P5ImageError.encodingFailed(format)
        }
        return data as Data
    }

    /// Writes an encoded image atomically to a file URL.
    public func write(
        to url: URL,
        format: P5ImageFormat,
        quality: CGFloat = 0.9
    ) throws {
        try encoded(as: format, quality: quality).write(to: url, options: .atomic)
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt16) -> UInt8 {
        UInt8(min(255, (UInt16(component) * 255 + alpha / 2) / alpha))
    }

    static func makeImage(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        makeProvider: (CFData) -> CGDataProvider? = CGDataProvider.init(data:)
    ) -> CGImage? {
        guard let provider = makeProvider(Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: P5RasterColorSpace.preferred(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func makeBitmapContext(
        data: UnsafeMutableRawPointer?,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: P5RasterColorSpace.preferred(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

public extension P5Sketch {
    /// Selects how image destination coordinates are interpreted.
    func imageMode(_ mode: P5ImageMode) {
        currentImageMode = mode
    }

    /// Draws an image at its natural logical size.
    func image(_ image: P5Image, _ x: CGFloat, _ y: CGFloat) {
        self.image(image, x, y, image.width, image.height)
    }

    /// Draws an entire image into a destination rectangle.
    func image(
        _ image: P5Image,
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat
    ) {
        let destination = imageRectangle(x, y, width, height)
        queueOperation(.image(image, source: nil, destination: destination))
    }

    /// Draws a cropped source region into a destination rectangle.
    ///
    /// Source values use top-left-origin logical image points and must remain
    /// within the image's logical bounds.
    func image(
        _ image: P5Image,
        destinationX: CGFloat,
        destinationY: CGFloat,
        destinationWidth: CGFloat,
        destinationHeight: CGFloat,
        sourceX: CGFloat,
        sourceY: CGFloat,
        sourceWidth: CGFloat,
        sourceHeight: CGFloat
    ) {
        let sourceValues = [sourceX, sourceY, sourceWidth, sourceHeight]
        precondition(sourceValues.allSatisfy(\.isFinite))
        precondition(sourceX >= 0 && sourceY >= 0 && sourceWidth >= 0 && sourceHeight >= 0)
        precondition(sourceX + sourceWidth <= image.width)
        precondition(sourceY + sourceHeight <= image.height)
        let source = CGRect(
            x: sourceX * image.pixelDensity,
            y: sourceY * image.pixelDensity,
            width: sourceWidth * image.pixelDensity,
            height: sourceHeight * image.pixelDensity
        )
        let destination = imageRectangle(
            destinationX,
            destinationY,
            destinationWidth,
            destinationHeight
        )
        queueOperation(.image(image, source: source, destination: destination))
    }

    /// Multiplies subsequent image colors by a normalized native color.
    func tint(_ color: P5Color) {
        queueOperation(.tint(color.cgColor))
    }

    /// Multiplies subsequent image colors by a Core Graphics color.
    func tint(_ color: CGColor) {
        queueOperation(.tint(color))
    }

    /// Disables image tinting.
    func noTint() {
        queueOperation(.noTint)
    }

    private func imageRectangle(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ fourth: CGFloat
    ) -> CGRect {
        precondition([first, second, third, fourth].allSatisfy(\.isFinite))
        switch currentImageMode {
        case .corner:
            return CGRect(x: first, y: second, width: third, height: fourth)
        case .corners:
            return CGRect(
                x: min(first, third),
                y: min(second, fourth),
                width: abs(third - first),
                height: abs(fourth - second)
            )
        case .center:
            return CGRect(
                x: first - third / 2,
                y: second - fourth / 2,
                width: third,
                height: fourth
            )
        }
    }
}
