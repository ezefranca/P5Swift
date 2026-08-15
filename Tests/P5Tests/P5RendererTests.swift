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

    @Test
    func testPointPolygonAndRoundedRectanglePrimitives() throws {
        let renderer = makeRenderer(width: 30, height: 20)
        renderer.addOperation(.stroke(red))
        renderer.addOperation(.strokeWeight(4))
        renderer.addOperation(.point(x: 3, y: 3))
        renderer.addOperation(.noStroke)
        renderer.addOperation(.point(x: 8, y: 3))
        renderer.addOperation(.fill(green))
        renderer.addOperation(
            .polygon([CGPoint(x: 2, y: 8), CGPoint(x: 8, y: 8), CGPoint(x: 5, y: 14)])
        )
        renderer.addOperation(.polygon([]))
        renderer.addOperation(.fill(red))
        renderer.addOperation(.roundedRect(x: 12, y: 2, width: 8, height: 8, cornerRadius: 3))
        renderer.addOperation(.roundedRect(x: 22, y: 2, width: 6, height: 6, cornerRadius: -1))

        let bitmap = try makeBitmap(width: 30, height: 20)
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 3, y: 3) == .red)
        #expect(bitmap.pixel(atX: 8, y: 3) == .clear)
        #expect(bitmap.pixel(atX: 5, y: 10) == .green)
        #expect(bitmap.pixel(atX: 12, y: 2).alpha < 20)
        #expect(bitmap.pixel(atX: 16, y: 5) == .red)
        #expect(bitmap.pixel(atX: 23, y: 3) == .red)
    }

    @Test
    func testAllArcClosureModes() throws {
        let renderer = makeRenderer(width: 32, height: 12)
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(
            .arc(x: 6, y: 6, width: 10, height: 10, start: 0, stop: .pi / 2, mode: .pie)
        )
        renderer.addOperation(
            .arc(x: 17, y: 6, width: 10, height: 10, start: 0, stop: .pi, mode: .chord)
        )
        renderer.addOperation(.noFill)
        renderer.addOperation(.stroke(green))
        renderer.addOperation(.strokeWeight(2))
        renderer.addOperation(
            .arc(x: 27, y: 6, width: 8, height: 8, start: .pi, stop: 2 * .pi, mode: .open)
        )

        let bitmap = try makeBitmap(width: 32, height: 12)
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 7, y: 7) == .red)
        #expect(bitmap.pixel(atX: 17, y: 8) == .red)
        #expect(bitmap.pixel(atX: 27, y: 2).green > 0)
    }

    @Test
    func testScaleShearApplyAndResetTransforms() throws {
        let renderer = makeRenderer(width: 24, height: 16)
        renderer.addOperation(.noStroke)
        renderer.addOperation(.fill(red))
        renderer.addOperation(.scale(x: 2, y: 2))
        renderer.addOperation(.rect(x: 1, y: 1, width: 2, height: 2))
        renderer.addOperation(.resetMatrix)
        renderer.addOperation(.shearX(0.5))
        renderer.addOperation(.shearY(0.25))
        renderer.addOperation(.rect(x: 8, y: 2, width: 2, height: 2))
        renderer.addOperation(.resetMatrix)
        renderer.addOperation(.applyMatrix(CGAffineTransform(translationX: 12, y: 0)))
        renderer.addOperation(.rect(x: 1, y: 8, width: 2, height: 2))
        renderer.addOperation(.resetMatrix)
        renderer.addOperation(.rect(x: 1, y: 12, width: 2, height: 2))

        let bitmap = try makeBitmap(width: 24, height: 16)
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 3, y: 3) == .red)
        #expect(bitmap.pixel(atX: 13, y: 9) == .red)
        #expect(bitmap.pixel(atX: 1, y: 13) == .red)
    }

    @Test
    func testCustomPathCommandsCurvesAndClosures() throws {
        let renderer = makeRenderer(width: 40, height: 30)
        renderer.addOperation(.noFill)
        renderer.addOperation(.stroke(red))
        renderer.addOperation(.strokeWeight(2))
        renderer.addOperation(.shape(commands: [], closure: .open))
        renderer.addOperation(
            .shape(
                commands: [
                    .vertex(CGPoint(x: 2, y: 2)),
                    .vertex(CGPoint(x: 10, y: 2)),
                    .bezier(
                        control1: CGPoint(x: 12, y: 2),
                        control2: CGPoint(x: 12, y: 8),
                        end: CGPoint(x: 10, y: 8)
                    ),
                    .quadratic(control: CGPoint(x: 6, y: 12), end: CGPoint(x: 2, y: 8)),
                    .curve(CGPoint(x: 2, y: 8)),
                    .curve(CGPoint(x: 4, y: 12)),
                    .curve(CGPoint(x: 8, y: 12)),
                    .curve(CGPoint(x: 10, y: 8)),
                ],
                closure: .close
            )
        )
        renderer.addOperation(
            .shape(
                commands: [
                    .curve(CGPoint(x: 14, y: 2)),
                    .curve(CGPoint(x: 16, y: 5)),
                    .curve(CGPoint(x: 18, y: 2)),
                ],
                closure: .open
            )
        )
        renderer.addOperation(
            .shape(
                commands: [
                    .curve(CGPoint(x: 20, y: 2)),
                    .curve(CGPoint(x: 22, y: 6)),
                    .curve(CGPoint(x: 26, y: 6)),
                    .curve(CGPoint(x: 28, y: 2)),
                ],
                closure: .open
            )
        )

        let bitmap = try makeBitmap(width: 40, height: 30)
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 2, y: 2).red > 0)
        #expect(bitmap.pixel(atX: 24, y: 6).red > 0)
    }

    @Test
    func testContoursUseEvenOddFillWithAndWithoutStroke() throws {
        let renderer = makeRenderer(width: 30, height: 14)
        let contour: [P5PathCommand] = [
            .vertex(CGPoint(x: 1, y: 1)),
            .vertex(CGPoint(x: 13, y: 1)),
            .vertex(CGPoint(x: 13, y: 13)),
            .vertex(CGPoint(x: 1, y: 13)),
            .beginContour,
            .vertex(CGPoint(x: 4, y: 4)),
            .vertex(CGPoint(x: 10, y: 4)),
            .vertex(CGPoint(x: 10, y: 10)),
            .vertex(CGPoint(x: 4, y: 10)),
            .endContour,
        ]
        renderer.addOperation(.fill(red))
        renderer.addOperation(.stroke(green))
        renderer.addOperation(.shape(commands: contour, closure: .close))
        renderer.addOperation(.noStroke)
        renderer.addOperation(.translate(x: 15, y: 0))
        renderer.addOperation(.shape(commands: contour, closure: .close))

        let bitmap = try makeBitmap(width: 30, height: 14)
        renderer.render(in: bitmap.context)

        #expect(bitmap.pixel(atX: 2, y: 2) == .red)
        #expect(bitmap.pixel(atX: 7, y: 7) == .clear)
        #expect(bitmap.pixel(atX: 17, y: 2) == .red)
        #expect(bitmap.pixel(atX: 22, y: 7) == .clear)
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
        makeDeviceRGBColor(red: 1, green: 0, blue: 0)
    }

    private var green: CGColor {
        makeDeviceRGBColor(red: 0, green: 1, blue: 0)
    }
}
