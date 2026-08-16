import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import P5

@Suite("P5 frame capture and animation export", .serialized)
struct P5FrameExportTests {
    @Test("Sketch capture is top-left-origin, density-aware, and non-destructive")
    @MainActor
    func capture() throws {
        let sketch = P5Sketch(size: CGSize(width: 6, height: 4))
        sketch.noLoop()
        sketch.background(P5Color(red: 0, green: 0, blue: 0))
        sketch.noStroke()
        sketch.fill(P5Color(red: 1, green: 0, blue: 0))
        sketch.rect(0, 0, 3, 2)

        let dense = try sketch.captureFrame(pixelDensity: 2)
        #expect(dense.pixelWidth == 12)
        #expect(dense.pixelHeight == 8)
        #expect(try dense.color(x: 0.5, y: 0.5).red == 1)
        #expect(try dense.color(x: 5, y: 3).red == 0)

        sketch.pixelDensity(1.5)
        let inherited = try sketch.captureFrame()
        #expect(inherited.pixelDensity == 1.5)
        #expect(try inherited.color(x: 0.5, y: 0.5).red == 1)

        let canvas = try #require(sketch.view as? P5SketchInternalView)
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try canvas.capture(pixelDensity: 1, makeContext: { _, _ in nil })
        }
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try canvas.capture(
                pixelDensity: 1,
                makeContext: P5SketchCaptureRuntime.makeContext,
                makeImage: { _ in nil }
            )
        }
    }

    @Test("Animated GIF export preserves frame order, timing, loops, and file output")
    func animatedGIF() throws {
        let red = try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2, height: 1,
                bytes: [
                    255, 0, 0, 255, 255, 0, 0, 255,
                ])
        )
        let green = try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2, height: 1,
                bytes: [
                    0, 255, 0, 255, 0, 255, 0, 255,
                ])
        )
        let sequence = P5FrameSequence(
            frames: [red, green],
            framesPerSecond: 12,
            loopCount: 3
        )
        #expect(sequence.frames.count == 2)
        #expect(sequence.framesPerSecond == 12)
        #expect(sequence.loopCount == 3)

        let data = try sequence.encodedGIF()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let second = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
        #expect(try P5Image(cgImage: first).color(x: 0, y: 0).red > 0.9)
        #expect(try P5Image(cgImage: second).color(x: 0, y: 0).green > 0.9)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            conformingTo: .gif
        )
        defer { try? FileManager.default.removeItem(at: file) }
        try sequence.writeGIF(to: file)
        #expect((try Data(contentsOf: file)).isEmpty == false)

        #expect(throws: P5ImageError.animationEncodingFailed) {
            _ = try sequence.encodedGIF(
                createDestination: { _, _, _, _ in nil },
                finalize: { _ in true }
            )
        }
        #expect(throws: P5ImageError.animationEncodingFailed) {
            _ = try sequence.encodedGIF(
                createDestination: CGImageDestinationCreateWithData,
                finalize: { _ in false }
            )
        }
        #expect(
            P5ImageError.animationEncodingFailed.errorDescription?.contains("animation") == true
        )
    }

    @Test("Flipped canvas geometry aligns half-point strokes with top raster pixels")
    @MainActor
    func flippedCoordinatesAndPixelAlignment() throws {
        let graphics = try P5Graphics(size: CGSize(width: 4, height: 4))
        graphics.clear()
        graphics.noFill()
        graphics.noSmooth()
        graphics.stroke(P5Color(red: 1, green: 1, blue: 1))
        graphics.strokeWeight(1)
        graphics.line(0.5, 0.5, 3.5, 0.5)
        let pixels = try graphics.snapshot().pixelBuffer()
        #expect(pixels.color(x: 1, y: 0).alpha == 1)
        #expect(pixels.color(x: 1, y: 3).alpha == 0)
    }

    @Test("Invalid frame capture and animation values terminate at public boundaries")
    func invalidValuesTerminateTheProcess() async {
        await #expect(processExitsWith: .failure) {
            _ = P5FrameSequence(frames: [], framesPerSecond: 1)
        }
        await #expect(processExitsWith: .failure) {
            let frame = try! P5Image(
                pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
            )
            _ = P5FrameSequence(frames: [frame], framesPerSecond: 0)
        }
        await #expect(processExitsWith: .failure) {
            let frame = try! P5Image(
                pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
            )
            _ = P5FrameSequence(frames: [frame], framesPerSecond: 1, loopCount: -1)
        }
        await #expect(processExitsWith: .failure) {
            let first = try! P5Image(
                pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
            )
            let second = try! P5Image(
                pixelBuffer: P5PixelBuffer(
                    width: 2, height: 1,
                    bytes: [
                        0, 0, 0, 0, 0, 0, 0, 0,
                    ])
            )
            _ = P5FrameSequence(frames: [first, second], framesPerSecond: 1)
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = try! P5Sketch(size: CGSize(width: 1, height: 1)).captureFrame(
                    pixelDensity: 0
                )
            }
        }
    }
}
