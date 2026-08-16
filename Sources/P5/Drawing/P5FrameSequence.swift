import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A validated immutable animation made from identically sized native images.
public struct P5FrameSequence: Sendable {
    /// Ordered frames from first presentation to last.
    public let frames: [P5Image]
    /// Number of frames presented per second.
    public let framesPerSecond: Double
    /// GIF repeat count, where zero repeats indefinitely.
    public let loopCount: Int

    /// Creates a frame sequence for deterministic animation export.
    ///
    /// - Precondition: Frames are nonempty and share dimensions and density;
    ///   frame rate is finite and positive; loop count is nonnegative.
    public init(frames: [P5Image], framesPerSecond: Double, loopCount: Int = 0) {
        precondition(frames.isEmpty == false)
        precondition(framesPerSecond.isFinite && framesPerSecond > 0)
        precondition(loopCount >= 0)
        let first = frames[0]
        precondition(
            frames.allSatisfy {
                $0.pixelWidth == first.pixelWidth && $0.pixelHeight == first.pixelHeight
                    && $0.pixelDensity == first.pixelDensity
            }
        )
        self.frames = frames
        self.framesPerSecond = framesPerSecond
        self.loopCount = loopCount
    }

    /// Encodes all frames as an animated GIF through ImageIO.
    public func encodedGIF() throws -> Data {
        try encodedGIF(
            createDestination: CGImageDestinationCreateWithData,
            finalize: CGImageDestinationFinalize
        )
    }

    func encodedGIF(
        createDestination: (CFMutableData, CFString, Int, CFDictionary?) -> CGImageDestination?,
        finalize: (CGImageDestination) -> Bool
    ) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = createDestination(
                data,
                UTType.gif.identifier as CFString,
                frames.count,
                nil
            )
        else {
            throw P5ImageError.animationEncodingFailed
        }
        let containerProperties =
            [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
            ] as CFDictionary
        CGImageDestinationSetProperties(destination, containerProperties)
        let frameProperties =
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: 1 / framesPerSecond
                ]
            ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.cgImage, frameProperties)
        }
        guard finalize(destination) else {
            throw P5ImageError.animationEncodingFailed
        }
        return data as Data
    }

    /// Writes an animated GIF atomically to a file URL.
    public func writeGIF(to url: URL) throws {
        try encodedGIF().write(to: url, options: .atomic)
    }
}
