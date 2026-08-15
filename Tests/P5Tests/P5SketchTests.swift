import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import P5

@MainActor
@Suite(.serialized)
struct P5SketchTests {
    @Test
    func initializationSetsCanvasDimensionsAndRunsSetupOnce() {
        let sketch = LifecycleSketch(size: CGSize(width: 100, height: 80))

        #expect(sketch.width == 100)
        #expect(sketch.height == 80)
        #expect(sketch.view.frame.size == CGSize(width: 100, height: 80))
        #expect(sketch.setupCallCount == 1)
        #expect(sketch.title == "Lifecycle")
        #expect(sketch.view.isFlipped)
        #expect(sketch.createVector(3, 4, 5) == P5Vector(x: 3, y: 4, z: 5))
    }

    @Test
    @available(*, deprecated)
    func deprecatedInitializerAndDefaultLifecycleRemainFunctional() throws {
        let sketch = P5Sketch(ofSize: CGSize(width: 20, height: 20))
        let bitmap = try #require(TestBitmap(width: 20, height: 20))

        draw(sketch, in: bitmap)

        #expect(sketch.width == 20)
        #expect(sketch.height == 20)
    }

    @Test
    func loopControlsRedrawAndDrawingOperations() throws {
        let sketch = LifecycleSketch(size: CGSize(width: 100, height: 80))
        let canvas = try #require(sketch.view as? P5SketchInternalView)

        canvas.draw(canvas.bounds)

        sketch.noLoop()
        sketch.loop()
        sketch.loop()
        sketch.frameRate(120)
        sketch.redraw()

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))

        sketch.noLoop()
        sketch.redraw()
        sketch.redraw()

        let bitmap = try #require(TestBitmap(width: 100, height: 80))
        draw(sketch, in: bitmap)

        #expect(sketch.drawCallCount == 1)
        #expect(bitmap.pixel(atX: 0, y: 0).alpha == 255)

        draw(sketch, in: bitmap)
        #expect(sketch.drawCallCount == 1)

        sketch.loop()
        draw(sketch, in: bitmap)
        sketch.noLoop()

        #expect(sketch.drawCallCount == 2)
    }

    @Test
    func coordinatorReplacesFixedSizeSketches() {
        let coordinator = P5SketchViewCoordinator(
            size: CGSize(width: 40, height: 30),
            makeSketch: LifecycleSketch.init(size:)
        )
        let originalSketch = coordinator.sketch

        coordinator.replaceSketch(
            for: CGSize(width: 80, height: 60),
            using: LifecycleSketch.init(size:)
        )

        #expect(coordinator.size == CGSize(width: 80, height: 60))
        #expect(coordinator.sketch !== originalSketch)
        #expect(coordinator.sketch.width == 80)
        #expect(originalSketch.view.superview == nil)
    }

    @Test
    func swiftUIViewCreatesAndUpdatesItsNativeCanvas() {
        _ = NSApplication.shared
        var createdSizes: [CGSize] = []

        let initialView = P5SketchView(
            size: CGSize(width: 100, height: 80)
        ) { size in
            createdSizes.append(size)
            return LifecycleSketch(size: size)
        }
        let hostingView = NSHostingView(rootView: initialView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 100, height: 80)
        hostingView.layoutSubtreeIfNeeded()
        _ = hostingView.fittingSize

        hostingView.rootView = P5SketchView(
            size: CGSize(width: 120, height: 90)
        ) { size in
            createdSizes.append(size)
            return LifecycleSketch(size: size)
        }
        hostingView.frame.size = CGSize(width: 120, height: 90)
        hostingView.layoutSubtreeIfNeeded()
        _ = hostingView.fittingSize

        #expect(createdSizes.first == CGSize(width: 100, height: 80))
        #expect(createdSizes.last == CGSize(width: 120, height: 90))
    }

    @Test
    func invalidFrameRateTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.frameRate(0)
            }
        }
    }

    @Test
    func invalidStrokeWeightTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.strokeWeight(0)
            }
        }
    }

    @Test
    func geometryPathsAndTransformsAreAvailableThroughTheSketchAPI() throws {
        let sketch = P5Sketch(size: CGSize(width: 48, height: 40))
        let red = makeDeviceRGBColor(red: 1, green: 0, blue: 0)
        let bitmap = try #require(TestBitmap(width: 48, height: 40))

        sketch.fill(red)
        sketch.noStroke()
        sketch.triangle(2, 2, 10, 2, 6, 10)
        sketch.quad(12, 2, 20, 2, 20, 10, 12, 10)
        sketch.rect(22, 2, 10, 8, cornerRadius: 3)
        sketch.angleMode(.degrees)
        sketch.arc(38, 6, 10, 10, 0, 180, .pie)
        sketch.regularPolygon(8, 18, radius: 5, sides: 5, rotation: -90)
        sketch.stroke(red)
        sketch.strokeWeight(3)
        sketch.point(18, 18)

        sketch.push()
        sketch.scale(2)
        sketch.resetMatrix()
        sketch.scale(1, 1)
        sketch.shearX(10)
        sketch.shearY(10)
        sketch.applyMatrix(.identity)
        sketch.resetMatrix()
        sketch.pop()

        sketch.beginShape()
        sketch.vertex(2, 26)
        sketch.vertex(8, 24)
        sketch.bezierVertex(12, 24, 12, 32, 8, 32)
        sketch.quadraticVertex(4, 34, 2, 26)
        sketch.endShape(.close)

        sketch.beginShape()
        sketch.curveVertex(14, 26)
        sketch.curveVertex(16, 24)
        sketch.curveVertex(22, 24)
        sketch.curveVertex(24, 26)
        sketch.endShape()

        sketch.beginShape()
        sketch.vertex(28, 24)
        sketch.vertex(46, 24)
        sketch.vertex(46, 38)
        sketch.vertex(28, 38)
        sketch.beginContour()
        sketch.vertex(34, 28)
        sketch.vertex(40, 28)
        sketch.vertex(40, 34)
        sketch.vertex(34, 34)
        sketch.endContour()
        sketch.endShape(.close)

        draw(sketch, in: bitmap)

        #expect(bitmap.pixel(atX: 6, y: 4) == .red)
        #expect(bitmap.pixel(atX: 18, y: 18).red > 0)
        #expect(P5ArcMode.allCases == [.open, .chord, .pie])
        #expect(P5ShapeClosure.allCases == [.open, .close])
        let encoded = try JSONEncoder().encode(P5ArcMode.chord)
        #expect(try JSONDecoder().decode(P5ArcMode.self, from: encoded) == .chord)
    }

    @Test
    func invalidGeometryStateTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5Sketch(size: CGSize(width: 10, height: 10)).vertex(0, 0)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.beginShape()
                sketch.beginShape()
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.beginShape()
                sketch.bezierVertex(0, 0, 1, 1, 2, 2)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.beginShape()
                sketch.quadraticVertex(0, 0, 1, 1)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.beginShape()
                sketch.beginContour()
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.beginShape()
                sketch.vertex(0, 0)
                sketch.endContour()
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5Sketch(size: CGSize(width: 10, height: 10)).endShape()
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                sketch.beginShape()
                sketch.vertex(0, 0)
                sketch.beginContour()
                sketch.vertex(1, 1)
                sketch.endShape()
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5Sketch(size: CGSize(width: 10, height: 10)).regularPolygon(
                    0,
                    0,
                    radius: 1,
                    sides: 2
                )
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5Sketch(size: CGSize(width: 10, height: 10)).regularPolygon(
                    0,
                    0,
                    radius: .nan,
                    sides: 3
                )
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5Sketch(size: CGSize(width: 10, height: 10)).regularPolygon(
                    0,
                    0,
                    radius: -1,
                    sides: 3
                )
            }
        }
    }

    private func draw(_ sketch: P5Sketch, in bitmap: TestBitmap) {
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.current = NSGraphicsContext(
            cgContext: bitmap.context,
            flipped: true
        )
        sketch.view.draw(sketch.view.bounds)
    }
}

@MainActor
private final class LifecycleSketch: P5Sketch {
    private(set) var setupCallCount = 0
    private(set) var drawCallCount = 0

    override func setup() {
        setupCallCount += 1
        title = "Lifecycle"
        frameRate(60)
        noLoop()
    }

    override func draw() {
        drawCallCount += 1

        let red = makeDeviceRGBColor(red: 1, green: 0, blue: 0)
        let green = makeDeviceRGBColor(red: 0, green: 1, blue: 0)

        background(red)
        fill(green)
        stroke(red)
        strokeWeight(2)
        line(1, 1, 20, 1)
        rect(2, 4, 10, 8)
        square(15, 4, 8)
        circle(30, 10, 8)
        ellipse(42, 10, 10, 6)
        push()
        translate(5, 5)
        rotate(.pi / 8)
        noFill()
        noStroke()
        pop()
    }
}
