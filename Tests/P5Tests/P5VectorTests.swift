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
    func componentOverloadsRemaindersAndEqualityMatchP5Semantics() {
        var vector = P5Vector.zero
        #expect(vector.set(P5Vector(x: 10, y: 20, z: 30)) == P5Vector(x: 10, y: 20, z: 30))
        #expect(vector.add(1, 2, 3) == P5Vector(x: 11, y: 22, z: 33))
        #expect(vector.sub(1, 2, 3) == P5Vector(x: 10, y: 20, z: 30))
        #expect(vector.mult(P5Vector(x: 2, y: 3, z: 4)) == P5Vector(x: 20, y: 60, z: 120))
        #expect(vector.div(P5Vector(x: 2, y: 3, z: 4)) == P5Vector(x: 10, y: 20, z: 30))
        #expect(vector.rem(7) == P5Vector(x: 3, y: 6, z: 2))
        #expect(vector.rem(P5Vector(x: 2, y: 4, z: 3)) == P5Vector(x: 1, y: 2, z: 2))
        #expect(vector.equals(P5Vector(x: 1, y: 2, z: 2)))
        #expect(!vector.equals(.zero))

        let lhs = P5Vector(x: 10, y: 20, z: 30)
        let rhs = P5Vector(x: 2, y: 4, z: 5)
        #expect(P5Vector.mult(lhs, rhs) == P5Vector(x: 20, y: 80, z: 150))
        #expect(P5Vector.div(lhs, rhs) == P5Vector(x: 5, y: 5, z: 6))
        #expect(P5Vector.rem(lhs, 6) == P5Vector(x: 4, y: 2, z: 0))
        #expect(P5Vector.rem(lhs, rhs) == P5Vector(x: 0, y: 0, z: 0))
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
    func explicitAngleModesConvertEveryAngularVectorOperation() {
        var vector = P5Vector(x: 2, y: 0)

        #expect(vector.heading(angleMode: .degrees) == 0)
        vector.setHeading(90, angleMode: .degrees)
        #expect(vector.isApproximately(P5Vector(x: 0, y: 2)))
        vector.rotate(90, angleMode: .degrees)
        #expect(vector.isApproximately(P5Vector(x: -2, y: 0)))
        #expect(
            P5Vector(x: 1).angleBetween(P5Vector(y: 1), angleMode: .degrees).isApproximately(90)
        )
        #expect(
            P5Vector.fromAngle(90, length: 3, angleMode: .degrees)
                .isApproximately(P5Vector(x: 0, y: 3))
        )
    }

    @Test
    func reflectionAndSphericalInterpolationHandleAllDirectionCases() {
        var reflected = P5Vector(x: 1, y: -1)
        #expect(reflected.reflect(P5Vector(y: 2)).isApproximately(P5Vector(x: 1, y: 1)))
        #expect(reflected.reflect(.zero).isApproximately(P5Vector(x: 1, y: 1)))
        #expect(
            P5Vector.reflect(P5Vector(x: -1, y: 1), normal: P5Vector(x: 2))
                .isApproximately(P5Vector(x: 1, y: 1))
        )

        var zero = P5Vector.zero
        #expect(zero.slerp(P5Vector(x: 2), 0.5) == P5Vector(x: 1))

        var parallel = P5Vector(x: 2)
        #expect(parallel.slerp(P5Vector(x: 4), 0.5).isApproximately(P5Vector(x: 3)))

        var regular = P5Vector(x: 2)
        #expect(
            regular.slerp(P5Vector(x: 0, y: 4), 0.5)
                .isApproximately(P5Vector(x: 4.5.squareRoot(), y: 4.5.squareRoot()))
        )

        var oppositeX = P5Vector(x: 2)
        #expect(
            oppositeX.slerp(P5Vector(x: -2), 0.5)
                .isApproximately(P5Vector(z: 2))
        )
        var oppositeY = P5Vector(y: 2)
        #expect(
            oppositeY.slerp(P5Vector(y: -2), 0.5)
                .isApproximately(P5Vector(z: -2))
        )
        #expect(
            P5Vector.slerp(P5Vector(x: 1), P5Vector(y: 1), 0.5)
                .isApproximately(P5Vector(x: 0.5.squareRoot(), y: 0.5.squareRoot()))
        )
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

    @Test
    func random3DCreatesUnitVectors() {
        var generator = SeededGenerator(state: 0x1234_5678_9ABC_DEF0)
        let seeded = P5Vector.random3D(using: &generator)
        let system = P5Vector.random3D()

        #expect(seeded.mag().isApproximately(1))
        #expect((-1...1).contains(seeded.z))
        #expect(system.mag().isApproximately(1))
        #expect((-1...1).contains(system.z))
    }

    @Test
    func invalidSphericalInterpolationTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            var vector = P5Vector(x: 1)
            vector.slerp(P5Vector(y: 1), .nan)
        }
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
