import CoreGraphics
import Testing

@testable import P5

@Suite
struct P5VectorTests {
    @Test
    func constructionCopyingAndCoreGraphicsBridges() {
        let zero = P5Vector.zero
        let vector = P5Vector(x: 1, y: 2, z: 3)
        let pointVector = P5Vector(CGPoint(x: 4, y: 5))
        let cgVector = P5Vector(CGVector(dx: 6, dy: 7))

        #expect(zero == P5Vector())
        #expect(vector.copy() == vector)
        #expect(vector.array() == [1, 2, 3])
        #expect(pointVector.point == CGPoint(x: 4, y: 5))
        #expect(cgVector.cgVector == CGVector(dx: 6, dy: 7))
    }

    @Test
    func p5StyleAndSwiftArithmeticProduceEquivalentValues() {
        var vector = P5Vector(x: 1, y: 2, z: 3)
        #expect(vector.set(2, 4, 6) == P5Vector(x: 2, y: 4, z: 6))
        #expect(vector.add(P5Vector(x: 1, y: 2, z: 3)) == P5Vector(x: 3, y: 6, z: 9))
        #expect(vector.sub(P5Vector(x: 1, y: 1, z: 1)) == P5Vector(x: 2, y: 5, z: 8))
        #expect(vector.mult(2) == P5Vector(x: 4, y: 10, z: 16))
        #expect(vector.div(2) == P5Vector(x: 2, y: 5, z: 8))

        let lhs = P5Vector(x: 2, y: 4, z: 6)
        let rhs = P5Vector(x: 1, y: 2, z: 3)
        #expect(P5Vector.add(lhs, rhs) == lhs + rhs)
        #expect(P5Vector.sub(lhs, rhs) == lhs - rhs)
        #expect(P5Vector.mult(lhs, 2) == lhs * 2)
        #expect(P5Vector.div(lhs, 2) == lhs / 2)
        #expect(-rhs == P5Vector(x: -1, y: -2, z: -3))
        #expect(2 * rhs == P5Vector(x: 2, y: 4, z: 6))

        var compound = lhs
        compound += rhs
        compound -= rhs
        compound *= 2
        compound /= 2
        #expect(compound == lhs)
    }

    @Test
    func magnitudeDirectionAndInterpolationMatchP5Semantics() {
        let vector = P5Vector(x: 3, y: 4)
        #expect(vector.magSq() == 25)
        #expect(vector.mag() == 5)
        #expect(vector.dot(P5Vector(x: 2, y: 1)) == 10)
        #expect(
            P5Vector(x: 1, y: 0, z: 0).cross(P5Vector(x: 0, y: 1, z: 0))
                == P5Vector(x: 0, y: 0, z: 1)
        )
        #expect(vector.dist(.zero) == 5)
        #expect(P5Vector.dist(vector, .zero) == 5)

        var normalized = vector
        #expect(normalized.normalize().isApproximately(P5Vector(x: 0.6, y: 0.8)))
        var zero = P5Vector.zero
        #expect(zero.normalize() == .zero)
        #expect(P5Vector.normalize(vector).isApproximately(P5Vector(x: 0.6, y: 0.8)))

        var limited = P5Vector(x: 6, y: 8)
        limited.limit(20)
        #expect(limited == P5Vector(x: 6, y: 8))
        #expect(limited.limit(5).isApproximately(vector))
        #expect(P5Vector.limit(P5Vector(x: 0, y: 10), 2).isApproximately(P5Vector(x: 0, y: 2)))

        var magnitude = vector
        #expect(magnitude.setMag(-10).isApproximately(P5Vector(x: -6, y: -8)))
        #expect(P5Vector.setMag(vector, 10).isApproximately(P5Vector(x: 6, y: 8)))

        var interpolation = P5Vector(x: 0, y: 2, z: 4)
        #expect(interpolation.lerp(P5Vector(x: 2, y: 4, z: 6), 0.5) == P5Vector(x: 1, y: 3, z: 5))
        #expect(
            P5Vector.lerp(.zero, P5Vector(x: 4, y: 6, z: 8), 0.25) == P5Vector(x: 1, y: 1.5, z: 2))
    }

    @Test
    func angularOperationsUseClockwiseCanvasRadians() {
        let right = P5Vector(x: 1, y: 0)
        let down = P5Vector(x: 0, y: 1)

        #expect(right.heading() == 0)
        #expect(right.angleBetween(down).isApproximately(.pi / 2))
        #expect(down.angleBetween(right).isApproximately(-.pi / 2))
        #expect(P5Vector.angleBetween(right, down).isApproximately(.pi / 2))

        var heading = P5Vector(x: 2, y: 0, z: 3)
        heading.setHeading(.pi / 2)
        #expect(heading.isApproximately(P5Vector(x: 0, y: 2, z: 3)))
        heading.rotate(.pi / 2)
        #expect(heading.isApproximately(P5Vector(x: -2, y: 0, z: 3)))

        #expect(P5Vector.fromAngle(.pi / 2, length: 4).isApproximately(P5Vector(x: 0, y: 4)))
    }

    @Test
    func random2DCreatesUnitVectors() {
        var generator = SeededGenerator(state: 0x1234_5678_9ABC_DEF0)
        let seeded = P5Vector.random2D(using: &generator)
        let system = P5Vector.random2D()

        #expect(seeded.mag().isApproximately(1))
        #expect(seeded.z == 0)
        #expect(system.mag().isApproximately(1))
        #expect(system.z == 0)
    }
}

private extension P5Vector {
    func isApproximately(_ other: Self, tolerance: CGFloat = 0.000_001) -> Bool {
        x.isApproximately(other.x, tolerance: tolerance)
            && y.isApproximately(other.y, tolerance: tolerance)
            && z.isApproximately(other.z, tolerance: tolerance)
    }
}

private extension CGFloat {
    func isApproximately(_ other: Self, tolerance: Self = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = (state &* 6_364_136_223_846_793_005) &+ 1
        return state
    }
}
