import CoreGraphics

/// An offscreen Core Graphics canvas that shares the complete P5 2D drawing API.
///
/// Drawing commands are retained until ``snapshot()`` is called. The snapshot
/// flushes those commands into a persistent bitmap, so later snapshots include
/// earlier pixels while transformation state starts fresh at each flush.
@MainActor
public final class P5Graphics: P5Sketch {
    private let bitmapContext: CGContext

    /// Creates a transparent offscreen canvas.
    ///
    /// - Parameters:
    ///   - size: Positive logical canvas extent in points.
    ///   - pixelDensity: Positive raster pixels per logical point.
    /// - Throws: ``P5ImageError/bitmapAllocationFailed`` when Core Graphics
    ///   cannot allocate the backing bitmap.
    public convenience init(size: CGSize, pixelDensity: CGFloat = 1) throws {
        try self.init(size: size, pixelDensity: pixelDensity, makeContext: Self.makeContext)
    }

    init(
        size: CGSize,
        pixelDensity: CGFloat,
        makeContext: (Int, Int) -> CGContext?
    ) throws {
        precondition(
            size.width.isFinite && size.width > 0 && size.height.isFinite && size.height > 0
        )
        precondition(pixelDensity.isFinite && pixelDensity > 0)
        let rasterWidth = size.width * pixelDensity
        let rasterHeight = size.height * pixelDensity
        precondition(
            rasterWidth <= CGFloat(Int.max) && rasterHeight <= CGFloat(Int.max)
        )
        let pixelWidth = Int(rasterWidth.rounded(.up))
        let pixelHeight = Int(rasterHeight.rounded(.up))
        guard
            let context = makeContext(pixelWidth, pixelHeight)
        else {
            throw P5ImageError.bitmapAllocationFailed
        }
        bitmapContext = context
        super.init(
            size: size,
            clock: P5ManualClock(),
            frameDriver: .manual,
            randomGenerator: P5RandomGenerator()
        )
        bitmapContext.translateBy(x: 0, y: CGFloat(pixelHeight))
        bitmapContext.scaleBy(x: pixelDensity, y: -pixelDensity)
        self.pixelDensity(pixelDensity)
        noLoop()
    }

    /// Flushes queued drawing and returns an immutable snapshot.
    public func snapshot() throws -> P5Image {
        try snapshot(makeImage: { $0.makeImage() })
    }

    func snapshot(makeImage: (CGContext) -> CGImage?) throws -> P5Image {
        renderQueuedOperations(in: bitmapContext)
        currentTransformValue = .identity
        transformStack.removeAll(keepingCapacity: true)
        guard let image = makeImage(bitmapContext) else {
            throw P5ImageError.bitmapAllocationFailed
        }
        return P5Image(cgImage: image, pixelDensity: pixelDensity())
    }

    /// Flushes drawing and returns editable straight-alpha RGBA8 pixels.
    public func loadPixels() throws -> P5PixelBuffer {
        try snapshot().pixelBuffer()
    }

    /// Replaces the complete offscreen raster with edited RGBA8 pixels.
    ///
    /// - Precondition: Dimensions and density match this graphics canvas.
    public func updatePixels(_ pixels: P5PixelBuffer) throws {
        let expectedWidth = Int((width * pixelDensity()).rounded(.up))
        let expectedHeight = Int((height * pixelDensity()).rounded(.up))
        precondition(pixels.width == expectedWidth && pixels.height == expectedHeight)
        precondition(pixels.pixelDensity == pixelDensity())
        clear()
        imageMode(.corner)
        image(try P5Image(pixelBuffer: pixels), 0, 0, width, height)
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: P5RasterColorSpace.preferred(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

public extension P5Sketch {
    /// Creates a persistent transparent offscreen drawing surface.
    ///
    /// - Parameters:
    ///   - width: Logical width in points.
    ///   - height: Logical height in points.
    ///   - pixelDensity: Optional density; the current canvas density is used by default.
    /// - Returns: A canvas that accepts the same two-dimensional drawing commands.
    /// - Throws: ``P5ImageError/bitmapAllocationFailed`` when Core Graphics
    ///   cannot allocate the offscreen bitmap.
    func createGraphics(
        _ width: CGFloat,
        _ height: CGFloat,
        pixelDensity: CGFloat? = nil
    ) throws -> P5Graphics {
        try P5Graphics(
            size: CGSize(width: width, height: height),
            pixelDensity: pixelDensity ?? self.pixelDensity()
        )
    }
}
