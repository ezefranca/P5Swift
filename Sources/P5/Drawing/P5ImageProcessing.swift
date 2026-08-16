import CoreGraphics
import CoreImage

/// Sampling quality used while resizing raster images.
public enum P5ImageInterpolation: String, Sendable, Hashable, Codable, CaseIterable {
    /// Chooses nearest-neighbor sampling.
    case none
    /// Chooses a fast low-quality interpolation.
    case low
    /// Balances interpolation quality and execution cost.
    case medium
    /// Chooses the highest Core Graphics interpolation quality.
    case high

    var cgQuality: CGInterpolationQuality {
        switch self {
        case .none:
            .none
        case .low:
            .low
        case .medium:
            .medium
        case .high:
            .high
        }
    }
}

/// Deterministic Core Image operations rendered through a software `CIContext`.
public enum P5ImageFilter: Sendable, Hashable, Codable {
    /// Inverts RGB components while preserving alpha.
    case invert
    /// Removes color saturation using native color controls.
    case grayscale
    /// Applies sepia toning with a normalized intensity.
    case sepia(intensity: CGFloat)
    /// Applies a Gaussian blur with a nonnegative radius in pixels.
    case gaussianBlur(radius: CGFloat)
    /// Reduces each color component to at least two discrete levels.
    case posterize(levels: Int)
}

public extension P5Image {
    /// Returns the color at a top-left-origin logical image coordinate.
    func color(x: CGFloat, y: CGFloat) throws -> P5Color {
        precondition(x.isFinite && y.isFinite)
        precondition(x >= 0 && y >= 0 && x < width && y < height)
        return try pixelBuffer().color(
            x: Int((x * pixelDensity).rounded(.down)),
            y: Int((y * pixelDensity).rounded(.down))
        )
    }

    /// Extracts a positive logical rectangle without resampling.
    func cropped(to rectangle: CGRect) throws -> P5Image {
        try cropped(to: rectangle, crop: { image, pixels in image.cropping(to: pixels) })
    }

    internal func cropped(
        to rectangle: CGRect,
        crop: (CGImage, CGRect) -> CGImage?
    ) throws -> P5Image {
        Self.validate(rectangle: rectangle)
        precondition(rectangle.minX >= 0 && rectangle.minY >= 0)
        precondition(rectangle.maxX <= width && rectangle.maxY <= height)
        let pixelRectangle = CGRect(
            x: rectangle.minX * pixelDensity,
            y: rectangle.minY * pixelDensity,
            width: rectangle.width * pixelDensity,
            height: rectangle.height * pixelDensity
        )
        guard let image = crop(cgImage, pixelRectangle) else {
            throw P5ImageError.processingFailed("crop")
        }
        return P5Image(cgImage: image, pixelDensity: pixelDensity)
    }

    /// Resamples to a positive logical size and optional destination density.
    func resized(
        to size: CGSize,
        pixelDensity destinationDensity: CGFloat? = nil,
        interpolation: P5ImageInterpolation = .high
    ) throws -> P5Image {
        let density = destinationDensity ?? pixelDensity
        precondition(
            size.width.isFinite && size.width > 0 && size.height.isFinite && size.height > 0
        )
        precondition(density.isFinite && density > 0)
        let destinationWidth = Int((size.width * density).rounded(.up))
        let destinationHeight = Int((size.height * density).rounded(.up))
        let image = try Self.renderBitmap(width: destinationWidth, height: destinationHeight) {
            context in
            context.interpolationQuality = interpolation.cgQuality
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: destinationWidth, height: destinationHeight)
            )
        }
        return P5Image(cgImage: image, pixelDensity: density)
    }

    /// Multiplies this image's alpha by another image's scaled alpha channel.
    func masked(with mask: P5Image) throws -> P5Image {
        let image = try Self.renderBitmap(width: pixelWidth, height: pixelHeight) { context in
            let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
            context.draw(cgImage, in: bounds)
            context.setBlendMode(.destinationIn)
            context.draw(mask.cgImage, in: bounds)
        }
        return P5Image(cgImage: image, pixelDensity: pixelDensity)
    }

    /// Applies a native filter and returns a software-rendered immutable image.
    func applying(_ filter: P5ImageFilter) throws -> P5Image {
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false,
        ])
        return try applying(filter) { image, extent in
            context.createCGImage(image, from: extent)
        }
    }

    internal func applying(
        _ filter: P5ImageFilter,
        render: (CIImage, CGRect) -> CGImage?
    ) throws -> P5Image {
        let source = CIImage(cgImage: cgImage)
        let output: CIImage
        switch filter {
        case .invert:
            output = source.applyingFilter("CIColorInvert")
        case .grayscale:
            output = source.applyingFilter(
                "CIColorControls",
                parameters: [kCIInputSaturationKey: 0]
            )
        case .sepia(let intensity):
            precondition(intensity.isFinite && (0...1).contains(intensity))
            output = source.applyingFilter(
                "CISepiaTone",
                parameters: [kCIInputIntensityKey: intensity]
            )
        case .gaussianBlur(let radius):
            precondition(radius.isFinite && radius >= 0)
            output = source.clampedToExtent().applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius]
            ).cropped(to: source.extent)
        case .posterize(let levels):
            precondition(levels >= 2)
            output = source.applyingFilter(
                "CIColorPosterize",
                parameters: ["inputLevels": levels]
            )
        }
        guard let rendered = render(output, source.extent) else {
            throw P5ImageError.processingFailed("filter")
        }
        return P5Image(cgImage: rendered, pixelDensity: pixelDensity)
    }

    internal static func renderBitmap(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
        try renderBitmap(
            width: width,
            height: height,
            makeContext: P5ImageProcessingRuntime.makeContext,
            makeImage: { $0.makeImage() },
            draw: draw
        )
    }

    internal static func renderBitmap(
        width: Int,
        height: Int,
        makeContext: (Int, Int) -> CGContext?,
        makeImage: (CGContext) -> CGImage?,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
        guard let context = makeContext(width, height) else {
            throw P5ImageError.bitmapAllocationFailed
        }
        draw(context)
        guard let image = makeImage(context) else {
            throw P5ImageError.bitmapAllocationFailed
        }
        return image
    }

    private static func validate(rectangle: CGRect) {
        precondition(
            [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height]
                .allSatisfy(\.isFinite)
        )
        precondition(rectangle.width > 0 && rectangle.height > 0)
    }
}

enum P5ImageProcessingRuntime {
    static func makeContext(width: Int, height: Int) -> CGContext? {
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
    /// Copies a logical source rectangle into a destination using corner coordinates.
    func copy(_ image: P5Image, source: CGRect, destination: CGRect) {
        precondition(source.width >= 0 && source.height >= 0)
        precondition(destination.width.isFinite && destination.height.isFinite)
        self.image(
            image,
            destinationX: destination.minX,
            destinationY: destination.minY,
            destinationWidth: destination.width,
            destinationHeight: destination.height,
            sourceX: source.minX,
            sourceY: source.minY,
            sourceWidth: source.width,
            sourceHeight: source.height
        )
    }

    /// Draws a logical source rectangle through a temporary compositing mode.
    func blend(
        _ image: P5Image,
        source: CGRect,
        destination: CGRect,
        mode: P5BlendMode
    ) {
        push()
        blendMode(mode)
        copy(image, source: source, destination: destination)
        pop()
    }
}
