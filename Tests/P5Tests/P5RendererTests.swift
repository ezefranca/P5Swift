import CoreGraphics
import Testing
@testable import P5

@Suite
struct P5RendererTests {
    @Test
    func testBackgroundFillsTheCanvas() throws {
        let renderer = makeRenderer(width: 8, height: 8)
        renderer.addOperation(.background(red))

        let bitmap = try makeBitmap(width: 8, height: 8)
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 0, y: 0) == .red)
        #expect(bitmap.pixel(atX: 7, y: 7) == .red)
    }

    @Test
    func testDefaultStyleUsesWhiteFillAndBlackStroke() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.rect(x: 2, y: 2, width: 6, height: 6))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 5, y: 5) == .white)

        let edge = bitmap.pixel(atX: 2, y: 5)
        #expect(edge.red < 255)
        #expect(edge.alpha == 255)
    }

    @Test
    func testFillAndNoStrokeDrawOnlyTheInterior() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.fill(red))
        renderer.addOperation(.noStroke)
        renderer.addOperation(.rect(x: 2, y: 2, width: 6, height: 6))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 5, y: 5) == .red)
        #expect(bitmap.pixel(atX: 1, y: 5) == .clear)
    }

    @Test
    func testNoFillAndStrokeWeightDrawOnlyTheOutline() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noFill)
        renderer.addOperation(.stroke(green))
        renderer.addOperation(.strokeWeight(2))
        renderer.addOperation(.rect(x: 2, y: 2, width: 6, height: 6))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 5, y: 5) == .clear)

        let edge = bitmap.pixel(atX: 2, y: 5)
        #expect(edge.green > 200)
        #expect(edge.alpha > 0)
    }

    @Test
    func testNoFillAndNoStrokeDrawNothing() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noFill)
        renderer.addOperation(.noStroke)
        renderer.addOperation(.rect(x: 1, y: 1, width: 8, height: 8))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 5, y: 5) == .clear)
    }

    @Test
    func testLineUsesStrokeAndNoStrokeDisablesIt() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.stroke(green))
        renderer.addOperation(.strokeWeight(2))
        renderer.addOperation(.line(x1: 1, y1: 3, x2: 9, y2: 3))
        renderer.addOperation(.noStroke)
        renderer.addOperation(.line(x1: 1, y1: 7, x2: 9, y2: 7))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        let line = bitmap.pixel(atX: 5, y: 3)
        #expect(line.green > 200)
        #expect(line.alpha > 0)
        #expect(bitmap.pixel(atX: 5, y: 7) == .clear)
    }

    @Test
    func testSquareUsesEqualWidthAndHeight() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.square(x: 2, y: 3, extent: 4))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 3, y: 4) == .red)
        #expect(bitmap.pixel(atX: 7, y: 4) == .clear)
        #expect(bitmap.pixel(atX: 3, y: 8) == .clear)
    }

    @Test
    func testEllipseUsesCenterCoordinatesAndDiameter() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.ellipse(x: 5, y: 5, width: 6, height: 6))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 5, y: 5) == .red)
        #expect(bitmap.pixel(atX: 1, y: 5) == .clear)
        #expect(bitmap.pixel(atX: 9, y: 5) == .clear)
    }

    @Test
    func testTranslateMovesSubsequentShapes() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.translate(x: 4, y: 3))
        renderer.addOperation(.rect(x: 0, y: 0, width: 2, height: 2))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 0, y: 0) == .clear)
        #expect(bitmap.pixel(atX: 4, y: 3) == .red)
    }

    @Test
    func testRotateTransformsSubsequentShapes() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.rotate(.pi / 2))
        renderer.addOperation(.rect(x: 1, y: -4, width: 3, height: 3))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 2, y: 2) == .red)
        #expect(bitmap.pixel(atX: 6, y: 2) == .clear)
    }

    @Test
    func testPushAndPopRestoreStyleAndTransform() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.translate(x: 3, y: 0))
        renderer.addOperation(.push)
        renderer.addOperation(.fill(green))
        renderer.addOperation(.translate(x: 3, y: 0))
        renderer.addOperation(.rect(x: 0, y: 2, width: 2, height: 2))
        renderer.addOperation(.pop)
        renderer.addOperation(.rect(x: 0, y: 6, width: 2, height: 2))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 6, y: 2) == .green)
        #expect(bitmap.pixel(atX: 3, y: 6) == .red)
        #expect(bitmap.pixel(atX: 6, y: 6) == .clear)
    }

    @Test
    func testUnmatchedPopIsIgnoredWithoutDiscardingOperations() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.pop)
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.rect(x: 2, y: 2, width: 3, height: 3))

        let bitmap = try makeBitmap()
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 3, y: 3) == .red)
    }

    @Test
    func testStylePersistsAcrossFramesButOperationsDoNot() throws {
        let renderer = makeRenderer()
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))

        let firstFrame = try makeBitmap()
        renderer.render(in: firstFrame.context)

        renderer.addOperation(.rect(x: 2, y: 2, width: 3, height: 3))
        let secondFrame = try makeBitmap()
        renderer.render(in: secondFrame.context)

        let thirdFrame = try makeBitmap()
        renderer.render(in: thirdFrame.context)

        #expect(firstFrame.pixel(atX: 3, y: 3) == .clear)
        #expect(secondFrame.pixel(atX: 3, y: 3) == .red)
        #expect(thirdFrame.pixel(atX: 3, y: 3) == .clear)
    }

    private func makeRenderer(
        width: CGFloat = 10,
        height: CGFloat = 10
    ) -> P5Renderer {
        let renderer = P5Renderer()
        renderer.size = CGSize(width: width, height: height)
        return renderer
    }

    private func makeBitmap(
        width: Int = 10,
        height: Int = 10
    ) throws -> TestBitmap {
        try #require(TestBitmap(width: width, height: height))
    }

    private var red: CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [1, 0, 0, 1]
        )!
    }

    private var green: CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [0, 1, 0, 1]
        )!
    }
}
