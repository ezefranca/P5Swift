import CoreGraphics
import Foundation

/// Scalar math utilities with the conventions used by p5.js sketches.
public enum P5Math {
    /// Constrains a value to a closed range.
    ///
    /// - Parameters:
    ///   - value: The value to constrain.
    ///   - lowerBound: The smallest permitted value.
    ///   - upperBound: The largest permitted value.
    /// - Returns: `value` clamped to the supplied bounds.
    public static func constrain(
        _ value: CGFloat,
        _ lowerBound: CGFloat,
        _ upperBound: CGFloat
    ) -> CGFloat {
        precondition(lowerBound <= upperBound)
        return min(max(value, lowerBound), upperBound)
    }

    /// Linearly maps a value from one range to another.
    ///
    /// This method corresponds to
    /// [p5.js `map()`](https://p5js.org/reference/p5/map/).
    ///
    /// - Parameters:
    ///   - value: The value in the source range.
    ///   - sourceStart: The source range's first endpoint.
    ///   - sourceStop: The source range's second endpoint.
    ///   - targetStart: The target range's first endpoint.
    ///   - targetStop: The target range's second endpoint.
    ///   - withinBounds: Whether to constrain the result to the target range.
    /// - Returns: The mapped value.
    public static func map(
        _ value: CGFloat,
        from sourceStart: CGFloat,
        to sourceStop: CGFloat,
        onto targetStart: CGFloat,
        to targetStop: CGFloat,
        withinBounds: Bool = false
    ) -> CGFloat {
        precondition(sourceStart != sourceStop)
        let result =
            targetStart
            + (targetStop - targetStart) * ((value - sourceStart) / (sourceStop - sourceStart))
        guard withinBounds else {
            return result
        }
        return constrain(result, min(targetStart, targetStop), max(targetStart, targetStop))
    }

    /// Interpolates between two values.
    ///
    /// - Parameters:
    ///   - start: The value returned for an amount of zero.
    ///   - stop: The value returned for an amount of one.
    ///   - amount: The interpolation amount. Values outside `0...1` extrapolate.
    /// - Returns: The interpolated value.
    public static func lerp(_ start: CGFloat, _ stop: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (stop - start) * amount
    }

    /// Normalizes a value in a range to an unbounded `0...1` scale.
    public static func norm(_ value: CGFloat, _ start: CGFloat, _ stop: CGFloat) -> CGFloat {
        map(value, from: start, to: stop, onto: 0, to: 1)
    }

    /// Returns the Euclidean distance between two 2D points.
    public static func dist(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat
    ) -> CGFloat {
        hypot(x2 - x1, y2 - y1)
    }

    /// Returns the Euclidean distance between two 3D points.
    public static func dist(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ z1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat,
        _ z2: CGFloat
    ) -> CGFloat {
        magnitude(x2 - x1, y2 - y1, z2 - z1)
    }

    /// Returns the magnitude of a 2D vector.
    public static func magnitude(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        hypot(x, y)
    }

    /// Returns the magnitude of a 3D vector.
    public static func magnitude(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGFloat {
        sqrt((x * x) + (y * y) + (z * z))
    }

    /// Converts degrees to radians.
    public static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    /// Converts radians to degrees.
    public static func degrees(_ radians: CGFloat) -> CGFloat {
        radians * 180 / .pi
    }

    /// Returns the smaller of two values.
    public static func minimum(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        Swift.min(first, second)
    }

    /// Returns the larger of two values.
    public static func maximum(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        Swift.max(first, second)
    }

    /// Rounds a value to the nearest integral value using the away-from-zero tie rule.
    public static func round(_ value: CGFloat) -> CGFloat {
        value.rounded(.toNearestOrAwayFromZero)
    }

    /// Rounds a value down to the nearest integral value.
    public static func floor(_ value: CGFloat) -> CGFloat {
        Foundation.floor(value)
    }

    /// Rounds a value up to the nearest integral value.
    public static func ceil(_ value: CGFloat) -> CGFloat {
        Foundation.ceil(value)
    }

    /// Returns the square of a value.
    public static func square(_ value: CGFloat) -> CGFloat {
        value * value
    }

    /// Returns the nonnegative square root of a nonnegative value.
    public static func squareRoot(_ value: CGFloat) -> CGFloat {
        precondition(value >= 0)
        return value.squareRoot()
    }

    /// Raises a base to an exponent.
    public static func power(_ base: CGFloat, _ exponent: CGFloat) -> CGFloat {
        Foundation.pow(base, exponent)
    }

    /// Returns the sine of an angle expressed in a selected mode.
    public static func sine(_ angle: CGFloat, angleMode: P5AngleMode = .radians) -> CGFloat {
        Foundation.sin(angleMode.radians(from: angle))
    }

    /// Returns the cosine of an angle expressed in a selected mode.
    public static func cosine(_ angle: CGFloat, angleMode: P5AngleMode = .radians) -> CGFloat {
        Foundation.cos(angleMode.radians(from: angle))
    }

    /// Returns the tangent of an angle expressed in a selected mode.
    public static func tangent(_ angle: CGFloat, angleMode: P5AngleMode = .radians) -> CGFloat {
        Foundation.tan(angleMode.radians(from: angle))
    }

    /// Returns the inverse sine in a selected angle mode.
    public static func arcSine(_ value: CGFloat, angleMode: P5AngleMode = .radians) -> CGFloat {
        angleMode.value(fromRadians: Foundation.asin(value))
    }

    /// Returns the inverse cosine in a selected angle mode.
    public static func arcCosine(_ value: CGFloat, angleMode: P5AngleMode = .radians) -> CGFloat {
        angleMode.value(fromRadians: Foundation.acos(value))
    }

    /// Returns the inverse tangent in a selected angle mode.
    public static func arcTangent(_ value: CGFloat, angleMode: P5AngleMode = .radians) -> CGFloat {
        angleMode.value(fromRadians: Foundation.atan(value))
    }

    /// Returns the quadrant-aware inverse tangent in a selected angle mode.
    public static func arcTangent2(
        _ y: CGFloat,
        _ x: CGFloat,
        angleMode: P5AngleMode = .radians
    ) -> CGFloat {
        angleMode.value(fromRadians: Foundation.atan2(y, x))
    }
}

public extension P5Sketch {
    /// Constrains a value to a closed range.
    func constrain(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        P5Math.constrain(value, lowerBound, upperBound)
    }

    /// Linearly maps a value from one range to another.
    func map(
        _ value: CGFloat,
        _ sourceStart: CGFloat,
        _ sourceStop: CGFloat,
        _ targetStart: CGFloat,
        _ targetStop: CGFloat,
        _ withinBounds: Bool = false
    ) -> CGFloat {
        P5Math.map(
            value,
            from: sourceStart,
            to: sourceStop,
            onto: targetStart,
            to: targetStop,
            withinBounds: withinBounds
        )
    }

    /// Interpolates between two values.
    func lerp(_ start: CGFloat, _ stop: CGFloat, _ amount: CGFloat) -> CGFloat {
        P5Math.lerp(start, stop, amount)
    }

    /// Normalizes a value in a range to an unbounded `0...1` scale.
    func norm(_ value: CGFloat, _ start: CGFloat, _ stop: CGFloat) -> CGFloat {
        P5Math.norm(value, start, stop)
    }

    /// Returns the Euclidean distance between two 2D points.
    func dist(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGFloat {
        P5Math.dist(x1, y1, x2, y2)
    }

    /// Returns the Euclidean distance between two 3D points.
    func dist(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ z1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat,
        _ z2: CGFloat
    ) -> CGFloat {
        P5Math.dist(x1, y1, z1, x2, y2, z2)
    }

    /// Returns the magnitude of a 2D vector.
    func mag(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        P5Math.magnitude(x, y)
    }

    /// Returns the magnitude of a 3D vector.
    func mag(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGFloat {
        P5Math.magnitude(x, y, z)
    }

    /// Converts degrees to radians.
    func radians(_ degrees: CGFloat) -> CGFloat {
        P5Math.radians(degrees)
    }

    /// Converts radians to degrees.
    func degrees(_ radians: CGFloat) -> CGFloat {
        P5Math.degrees(radians)
    }

    /// Selects the unit used by sketch rotation and trigonometric methods.
    func angleMode(_ mode: P5AngleMode) {
        currentAngleMode = mode
    }

    /// Returns the smaller of two values.
    func min(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        P5Math.minimum(first, second)
    }

    /// Returns the larger of two values.
    func max(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        P5Math.maximum(first, second)
    }

    /// Rounds a value to the nearest integral value.
    func round(_ value: CGFloat) -> CGFloat {
        P5Math.round(value)
    }

    /// Rounds a value down to the nearest integral value.
    func floor(_ value: CGFloat) -> CGFloat {
        P5Math.floor(value)
    }

    /// Rounds a value up to the nearest integral value.
    func ceil(_ value: CGFloat) -> CGFloat {
        P5Math.ceil(value)
    }

    /// Returns the square of a value.
    func sq(_ value: CGFloat) -> CGFloat {
        P5Math.square(value)
    }

    /// Returns the nonnegative square root of a nonnegative value.
    func sqrt(_ value: CGFloat) -> CGFloat {
        P5Math.squareRoot(value)
    }

    /// Raises a base to an exponent.
    func pow(_ base: CGFloat, _ exponent: CGFloat) -> CGFloat {
        P5Math.power(base, exponent)
    }

    /// Returns the sine of an angle in the current angle mode.
    func sin(_ angle: CGFloat) -> CGFloat {
        P5Math.sine(angle, angleMode: currentAngleMode)
    }

    /// Returns the cosine of an angle in the current angle mode.
    func cos(_ angle: CGFloat) -> CGFloat {
        P5Math.cosine(angle, angleMode: currentAngleMode)
    }

    /// Returns the tangent of an angle in the current angle mode.
    func tan(_ angle: CGFloat) -> CGFloat {
        P5Math.tangent(angle, angleMode: currentAngleMode)
    }

    /// Returns the inverse sine in the current angle mode.
    func asin(_ value: CGFloat) -> CGFloat {
        P5Math.arcSine(value, angleMode: currentAngleMode)
    }

    /// Returns the inverse cosine in the current angle mode.
    func acos(_ value: CGFloat) -> CGFloat {
        P5Math.arcCosine(value, angleMode: currentAngleMode)
    }

    /// Returns the inverse tangent in the current angle mode.
    func atan(_ value: CGFloat) -> CGFloat {
        P5Math.arcTangent(value, angleMode: currentAngleMode)
    }

    /// Returns the quadrant-aware inverse tangent in the current angle mode.
    func atan2(_ y: CGFloat, _ x: CGFloat) -> CGFloat {
        P5Math.arcTangent2(y, x, angleMode: currentAngleMode)
    }
}
