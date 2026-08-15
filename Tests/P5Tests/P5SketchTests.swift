import AppKit
import CoreGraphics
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
