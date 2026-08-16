import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import P5

#if canImport(AppKit)
    import AppKit
#endif

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
        #if canImport(AppKit)
            #expect(sketch.view.isFlipped)
        #endif
        #expect(sketch.createVector(3, 4, 5) == P5Vector(x: 3, y: 4, z: 5))
    }

    @Test
    func canvasResizingDensityAndDisplayMetricsStaySynchronized() throws {
        let sketch = P5Sketch(size: CGSize(width: 20, height: 10))
        sketch.noLoop()

        let detached = sketch.canvasMetrics()
        #expect(detached.size == CGSize(width: 20, height: 10))
        #expect(detached.displayScale > 0)
        #expect(detached.pixelDensity == 1)
        #expect(detached.displaySize.width > 0)
        #expect(detached.displaySize.height > 0)
        #expect(detached.safeAreaInsets == P5EdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
        #expect(detached.isFullScreen == false)

        sketch.resizeCanvas(32, 24)
        sketch.pixelDensity(2)
        #expect(sketch.width == 32)
        #expect(sketch.height == 24)
        #expect(sketch.view.frame.size == CGSize(width: 32, height: 24))
        #expect(sketch.view.bounds.size == CGSize(width: 32, height: 24))
        #expect(sketch.pixelDensity() == 2)
        #if canImport(AppKit)
            #expect(sketch.view.layer?.contentsScale == 2)
        #else
            #expect(sketch.view.layer.contentsScale == 2)
        #endif

        #if canImport(AppKit)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 32, height: 24),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = sketch.view
            let attached = sketch.canvasMetrics()
            #expect(attached.size == CGSize(width: 32, height: 24))
            #expect(attached.displayScale == window.backingScaleFactor)
            #expect(attached.pixelDensity == 2)
            #expect(attached.isFullScreen == false)
            #expect(P5SketchInternalView.isFullScreen(nil) == false)
            #expect(P5SketchInternalView.isFullScreen(.fullScreen))
        #endif

        let bitmap = try #require(TestBitmap(width: 32, height: 24))
        sketch.background(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        sketch.redraw()
        drawSketch(sketch, in: bitmap)
        let resizedPixel = bitmap.pixel(atX: 31, y: 23)
        #expect(resizedPixel.red == 255)
        #expect(resizedPixel.alpha == 255)
    }

    @Test
    func sceneTransitionsPreserveTheExplicitLoopPreference() throws {
        let sketch = P5Sketch(size: CGSize(width: 20, height: 20))
        let canvas = try #require(sketch.view as? P5SketchInternalView)
        #expect(P5ScenePhase.allCases == [.active, .inactive, .background])
        #expect(
            try JSONDecoder().decode(
                P5ScenePhase.self,
                from: JSONEncoder().encode(P5ScenePhase.background)
            ) == .background
        )

        sketch.pause()
        sketch.pause()
        #expect(sketch.isPaused)
        #expect(canvas.isLooping == false)
        sketch.loop()
        #expect(canvas.isLooping == false)
        sketch.resume()
        sketch.resume()
        #expect(sketch.isPaused == false)
        #expect(canvas.isLooping)

        sketch.scenePhaseChanged(to: .inactive)
        #expect(sketch.scenePhase == .inactive)
        #expect(sketch.isPaused)
        sketch.noLoop()
        sketch.scenePhaseChanged(to: .background)
        sketch.scenePhaseChanged(to: .active)
        #expect(sketch.isPaused == false)
        #expect(canvas.isLooping == false)

        sketch.loop()
        #expect(canvas.isLooping)
        sketch.scenePhaseChanged(to: .background)
        sketch.scenePhaseChanged(to: .active)
        #expect(canvas.isLooping)
        sketch.noLoop()
    }

    @Test
    @available(*, deprecated)
    func deprecatedInitializerAndDefaultLifecycleRemainFunctional() throws {
        let sketch = P5Sketch(ofSize: CGSize(width: 20, height: 20))
        let bitmap = try #require(TestBitmap(width: 20, height: 20))

        drawSketch(sketch, in: bitmap)

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
        drawSketch(sketch, in: bitmap)

        #expect(sketch.drawCallCount == 1)
        #expect(bitmap.pixel(atX: 0, y: 0).alpha == 255)

        drawSketch(sketch, in: bitmap)
        #expect(sketch.drawCallCount == 1)

        sketch.loop()
        drawSketch(sketch, in: bitmap)
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

    #if canImport(AppKit)
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
    #endif

    @Test
    func invalidFrameRateTerminatesTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.frameRate(0)
                }
            }
        #endif
    }

    @Test
    func invalidCanvasConfigurationTerminatesTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Sketch(size: CGSize(width: 0, height: 1))
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Sketch(size: CGSize(width: CGFloat.nan, height: 1))
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Sketch(size: CGSize(width: 1, height: 0))
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Sketch(size: CGSize(width: 1, height: CGFloat.infinity))
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1)).resizeCanvas(-1, 1)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1))
                        .resizeCanvas(.infinity, 1)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1)).resizeCanvas(1, -1)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1)).resizeCanvas(1, .nan)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1)).pixelDensity(0)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1)).pixelDensity(-.infinity)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 1, height: 1)).pixelDensity(.nan)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5EdgeInsets(top: -1, left: 0, bottom: 0, right: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5EdgeInsets(top: 0, left: .nan, bottom: 0, right: 0)
            }
        #endif
    }

    @Test
    func invalidStrokeWeightTerminatesTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.strokeWeight(0)
                }
            }
        #endif
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
        sketch.applyMatrix(CGAffineTransform.identity)
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

        drawSketch(sketch, in: bitmap)

        #expect(bitmap.pixel(atX: 6, y: 4) == .red)
        #expect(bitmap.pixel(atX: 18, y: 18).red > 0)
        #expect(P5ArcMode.allCases == [.open, .chord, .pie])
        #expect(P5ShapeClosure.allCases == [.open, .close])
        let encoded = try JSONEncoder().encode(P5ArcMode.chord)
        #expect(try JSONDecoder().decode(P5ArcMode.self, from: encoded) == .chord)
    }

    @Test
    func invalidGeometryStateTerminatesTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).vertex(0, 0)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.beginShape()
                    sketch.beginShape()
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.beginShape()
                    sketch.bezierVertex(0, 0, 1, 1, 2, 2)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.beginShape()
                    sketch.quadraticVertex(0, 0, 1, 1)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.beginShape()
                    sketch.beginContour()
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
                    sketch.beginShape()
                    sketch.vertex(0, 0)
                    sketch.endContour()
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Sketch(size: CGSize(width: 10, height: 10)).endShape()
                }
            }
        #endif
        #if os(macOS)
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
        #endif
        #if os(macOS)
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
        #endif
        #if os(macOS)
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
        #endif
        #if os(macOS)
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
        #endif
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
