import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import P5

@Suite("P5 reusable shapes and transformations")
struct P5ShapeTransformTests {
    @Test("Affine values compose, invert, apply, and serialize")
    func transformValues() throws {
        #expect(P5Transform.identity.cgAffineTransform == .identity)
        let transform = P5Transform(a: 2, b: 1, c: 0.5, d: 3, tx: 4, ty: 5)
        #expect(P5Transform(transform.cgAffineTransform) == transform)
        #expect(
            try JSONDecoder().decode(
                P5Transform.self,
                from: JSONEncoder().encode(transform)
            ) == transform
        )

        let translated = P5Transform.identity.translatedBy(x: 3, y: 4)
        #expect(translated.applying(to: CGPoint(x: 1, y: 2)) == CGPoint(x: 4, y: 6))
        let scaled = translated.scaledBy(x: 2, y: 3)
        let rotated = scaled.rotated(by: .pi / 2)
        let concatenated = P5Transform.identity.concatenating(rotated)
        #expect(concatenated == rotated)
        let inverse = try #require(transform.inverted)
        let restored = inverse.applying(to: transform.applying(to: CGPoint(x: 7, y: 9)))
        #expect(abs(restored.x - 7) < 0.000_001)
        #expect(abs(restored.y - 9) < 0.000_001)
        #expect(P5Transform(a: 1, b: 2, c: 2, d: 4).inverted == nil)
        #expect(
            P5Transform(a: .greatestFiniteMagnitude, d: .greatestFiniteMagnitude).inverted == nil
        )
    }

    @Test("Core Graphics paths import, export, transform, contain, and serialize")
    func reusableShapes() throws {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 9, y: 1))
        path.addQuadCurve(to: CGPoint(x: 9, y: 5), control: CGPoint(x: 11, y: 3))
        path.addCurve(
            to: CGPoint(x: 1, y: 9),
            control1: CGPoint(x: 9, y: 8),
            control2: CGPoint(x: 4, y: 9)
        )
        path.closeSubpath()

        let shape = P5Shape(path: path)
        #expect(shape.elements.count == 5)
        #expect(P5Shape(path: shape.cgPath) == shape)
        #expect(shape.bounds.minX == 1)
        #expect(shape.bounds.maxX > 9)
        #expect(shape.contains(CGPoint(x: 5, y: 4)))
        #expect(shape.contains(CGPoint(x: 20, y: 20)) == false)
        #expect(
            try JSONDecoder().decode(
                P5Shape.self,
                from: JSONEncoder().encode(shape)
            ) == shape
        )

        let moved = shape.applying(P5Transform.identity.translatedBy(x: 10, y: 20))
        #expect(moved.bounds.minX == 11)
        #expect(moved.bounds.minY == 21)
        #expect(moved.elements.count == shape.elements.count)

        let outer = CGMutablePath()
        outer.addRect(CGRect(x: 0, y: 0, width: 20, height: 20))
        outer.addRect(CGRect(x: 5, y: 5, width: 10, height: 10))
        let evenOdd = P5Shape(path: outer, fillRule: .evenOdd)
        #expect(evenOdd.contains(CGPoint(x: 2, y: 2)))
        #expect(evenOdd.contains(CGPoint(x: 10, y: 10)) == false)
        #expect(P5Shape(elements: []).cgPath.isEmpty)
    }

    @Test("Reusable shapes draw directly and custom builders return reusable geometry")
    @MainActor
    func sketchShapesAndMatrixInspection() throws {
        let sketch = P5Sketch(size: CGSize(width: 32, height: 24))
        sketch.noLoop()
        sketch.fill(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        sketch.noStroke()

        sketch.beginShape()
        sketch.vertex(1, 1)
        sketch.vertex(7, 1)
        sketch.vertex(7, 7)
        sketch.vertex(1, 7)
        let square = sketch.endShape(.close)
        #expect(square.elements.count == 5)
        sketch.shape(square.applying(P5Transform.identity.translatedBy(x: 10, y: 0)))

        #expect(sketch.currentTransform == .identity)
        sketch.translate(2, 3)
        #expect(sketch.currentTransform.tx == 2)
        #expect(sketch.currentTransform.ty == 3)
        sketch.push()
        sketch.rotate(.pi / 2)
        sketch.scale(2)
        sketch.scale(1, 3)
        sketch.shearX(0.1)
        sketch.shearY(0.2)
        sketch.applyMatrix(P5Transform(tx: 1, ty: 2))
        sketch.applyMatrix(CGAffineTransform(translationX: 3, y: 4))
        #expect(sketch.currentTransform != P5Transform.identity)
        sketch.pop()
        #expect(sketch.currentTransform == P5Transform.identity.translatedBy(x: 2, y: 3))
        sketch.pop()
        #expect(sketch.currentTransform == P5Transform.identity.translatedBy(x: 2, y: 3))
        sketch.resetMatrix()
        #expect(sketch.currentTransform == .identity)

        let bitmap = try #require(TestBitmap(width: 32, height: 24))
        sketch.redraw()
        draw(sketch, in: bitmap)
        #expect(bitmap.pixel(atX: 3, y: 3).red == 255)
        #expect(bitmap.pixel(atX: 13, y: 3).red == 255)
    }

    @MainActor
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

    @Test("Invalid transform and shape coordinates terminate at the public boundary")
    func invalidGeometryTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            _ = P5Transform(a: .nan)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.translatedBy(x: .nan, y: 0)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.translatedBy(x: 0, y: .infinity)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.rotated(by: .nan)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.scaledBy(x: .infinity, y: 1)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.scaledBy(x: 1, y: .nan)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.applying(to: CGPoint(x: CGFloat.nan, y: 0))
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Transform.identity.applying(to: CGPoint(x: 0, y: CGFloat.infinity))
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Shape(elements: [.move(to: CGPoint(x: CGFloat.nan, y: 0))])
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Shape(elements: []).contains(CGPoint(x: CGFloat.infinity, y: 0))
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Shape(elements: []).contains(CGPoint(x: 0, y: CGFloat.nan))
        }
    }
}
