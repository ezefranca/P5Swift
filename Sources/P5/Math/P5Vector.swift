import CoreGraphics

/// A two- or three-dimensional vector for creative-coding math and motion.
///
/// `P5Vector` is the native Swift counterpart to
/// [p5.js `p5.Vector`](https://p5js.org/reference/p5/p5.Vector/). It has value
/// semantics, uses `CGFloat` to interoperate with Core Graphics, and supports
/// both p5-style mutating methods and Swift arithmetic operators.
///
/// Angular APIs use radians by default. Overloads accepting ``P5AngleMode`` keep
/// standalone vectors explicit and independent from a sketch's mutable settings.
@frozen
public struct P5Vector: Sendable, Hashable, Codable {
    /// The x component.
    public var x: CGFloat

    /// The y component.
    public var y: CGFloat

    /// The z component.
    public var z: CGFloat

    /// Creates a vector from its components.
    public init(x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Creates a two-dimensional vector from a Core Graphics point.
    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    /// Creates a two-dimensional vector from a Core Graphics vector.
    public init(_ vector: CGVector) {
        self.init(x: vector.dx, y: vector.dy)
    }

    /// A vector whose components are all zero.
    public static let zero = Self()

    /// The x and y components represented as a Core Graphics point.
    public var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    /// The x and y components represented as a Core Graphics vector.
    public var cgVector: CGVector {
        CGVector(dx: x, dy: y)
    }

    /// Returns a value-semantic copy.
    ///
    /// This method corresponds to
    /// [p5.js `copy()`](https://p5js.org/reference/p5.Vector/copy/).
    public func copy() -> Self {
        self
    }

    /// Returns the components in x, y, z order.
    ///
    /// This method corresponds to
    /// [p5.js `array()`](https://p5js.org/reference/p5.Vector/array/).
    public func array() -> [CGFloat] {
        [x, y, z]
    }
}

// MARK: - Component arithmetic

public extension P5Vector {
    /// Replaces all components with another vector and returns the updated value.
    @discardableResult
    mutating func set(_ other: Self) -> Self {
        self = other
        return self
    }

    /// Replaces all components and returns the updated vector.
    ///
    /// This method corresponds to
    /// [p5.js `set()`](https://p5js.org/reference/p5.Vector/set/).
    @discardableResult
    mutating func set(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) -> Self {
        self = Self(x: x, y: y, z: z)
        return self
    }

    /// Adds another vector in place and returns the updated vector.
    ///
    /// This method corresponds to
    /// [p5.js `add()`](https://p5js.org/reference/p5.Vector/add/).
    @discardableResult
    mutating func add(_ other: Self) -> Self {
        self += other
        return self
    }

    /// Adds individual components in place and returns the updated vector.
    @discardableResult
    mutating func add(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) -> Self {
        add(Self(x: x, y: y, z: z))
    }

    /// Subtracts another vector in place and returns the updated vector.
    ///
    /// This method corresponds to
    /// [p5.js `sub()`](https://p5js.org/reference/p5.Vector/sub/).
    @discardableResult
    mutating func sub(_ other: Self) -> Self {
        self -= other
        return self
    }

    /// Subtracts individual components in place and returns the updated vector.
    @discardableResult
    mutating func sub(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) -> Self {
        sub(Self(x: x, y: y, z: z))
    }

    /// Multiplies every component in place and returns the updated vector.
    ///
    /// This method corresponds to
    /// [p5.js `mult()`](https://p5js.org/reference/p5.Vector/mult/).
    @discardableResult
    mutating func mult(_ scalar: CGFloat) -> Self {
        self *= scalar
        return self
    }

    /// Multiplies individual components in place and returns the updated vector.
    @discardableResult
    mutating func mult(_ other: Self) -> Self {
        precondition(other.x.isFinite && other.y.isFinite && other.z.isFinite)
        x *= other.x
        y *= other.y
        z *= other.z
        return self
    }

    /// Divides every component in place and returns the updated vector.
    ///
    /// The scalar must be finite and nonzero. This method corresponds to
    /// [p5.js `div()`](https://p5js.org/reference/p5.Vector/div/).
    @discardableResult
    mutating func div(_ scalar: CGFloat) -> Self {
        self /= scalar
        return self
    }

    /// Divides individual components in place and returns the updated vector.
    @discardableResult
    mutating func div(_ other: Self) -> Self {
        precondition(
            other.x.isFinite && other.x != 0 && other.y.isFinite && other.y != 0
                && other.z.isFinite && other.z != 0
        )
        x /= other.x
        y /= other.y
        z /= other.z
        return self
    }

    /// Replaces each component with its floating-point remainder after division.
    @discardableResult
    mutating func rem(_ divisor: CGFloat) -> Self {
        precondition(divisor.isFinite && divisor != 0)
        return rem(Self(x: divisor, y: divisor, z: divisor))
    }

    /// Applies a component-wise floating-point remainder operation.
    @discardableResult
    mutating func rem(_ divisor: Self) -> Self {
        precondition(
            divisor.x.isFinite && divisor.x != 0 && divisor.y.isFinite && divisor.y != 0
                && divisor.z.isFinite && divisor.z != 0
        )
        x.formTruncatingRemainder(dividingBy: divisor.x)
        y.formTruncatingRemainder(dividingBy: divisor.y)
        z.formTruncatingRemainder(dividingBy: divisor.z)
        return self
    }

    /// Reports whether all three components exactly equal another vector.
    func equals(_ other: Self) -> Bool {
        self == other
    }

    /// Adds two vectors without changing either input.
    static func add(_ lhs: Self, _ rhs: Self) -> Self {
        lhs + rhs
    }

    /// Subtracts two vectors without changing either input.
    static func sub(_ lhs: Self, _ rhs: Self) -> Self {
        lhs - rhs
    }

    /// Multiplies a vector without changing the input.
    static func mult(_ vector: Self, _ scalar: CGFloat) -> Self {
        vector * scalar
    }

    /// Divides a vector without changing the input.
    static func div(_ vector: Self, _ scalar: CGFloat) -> Self {
        vector / scalar
    }

    /// Returns the component-wise product of two vectors.
    static func mult(_ lhs: Self, _ rhs: Self) -> Self {
        var result = lhs
        result.mult(rhs)
        return result
    }

    /// Returns the component-wise quotient of two vectors.
    static func div(_ lhs: Self, _ rhs: Self) -> Self {
        var result = lhs
        result.div(rhs)
        return result
    }

    /// Returns the component-wise remainder of a vector and scalar.
    static func rem(_ vector: Self, _ divisor: CGFloat) -> Self {
        var result = vector
        result.rem(divisor)
        return result
    }

    /// Returns the component-wise remainder of two vectors.
    static func rem(_ lhs: Self, _ rhs: Self) -> Self {
        var result = lhs
        result.rem(rhs)
        return result
    }
}

// MARK: - Magnitude and direction

public extension P5Vector {
    /// Returns the squared magnitude without calculating a square root.
    ///
    /// This method corresponds to
    /// [p5.js `magSq()`](https://p5js.org/reference/p5.Vector/magSq/).
    func magSq() -> CGFloat {
        (x * x) + (y * y) + (z * z)
    }

    /// Returns the vector's magnitude.
    ///
    /// This method corresponds to
    /// [p5.js `mag()`](https://p5js.org/reference/p5.Vector/mag/).
    func mag() -> CGFloat {
        magSq().squareRoot()
    }

    /// Returns the dot product with another vector.
    ///
    /// This method corresponds to
    /// [p5.js `dot()`](https://p5js.org/reference/p5.Vector/dot/).
    func dot(_ other: Self) -> CGFloat {
        (x * other.x) + (y * other.y) + (z * other.z)
    }

    /// Returns the cross product with another vector.
    ///
    /// This method corresponds to
    /// [p5.js `cross()`](https://p5js.org/reference/p5.Vector/cross/).
    func cross(_ other: Self) -> Self {
        Self(
            x: (y * other.z) - (z * other.y),
            y: (z * other.x) - (x * other.z),
            z: (x * other.y) - (y * other.x)
        )
    }

    /// Returns the distance to another vector.
    ///
    /// This method corresponds to
    /// [p5.js `dist()`](https://p5js.org/reference/p5.Vector/dist/).
    func dist(_ other: Self) -> CGFloat {
        (self - other).mag()
    }

    /// Scales the vector to unit length, leaving a zero vector unchanged.
    ///
    /// This method corresponds to
    /// [p5.js `normalize()`](https://p5js.org/reference/p5.Vector/normalize/).
    @discardableResult
    mutating func normalize() -> Self {
        let magnitude = mag()
        guard magnitude != 0 else { return self }
        self /= magnitude
        return self
    }

    /// Limits the vector to a maximum nonnegative magnitude.
    ///
    /// This method corresponds to
    /// [p5.js `limit()`](https://p5js.org/reference/p5.Vector/limit/).
    @discardableResult
    mutating func limit(_ maximum: CGFloat) -> Self {
        precondition(maximum.isFinite && maximum >= 0)
        if magSq() > maximum * maximum {
            normalize()
            mult(maximum)
        }
        return self
    }

    /// Sets the magnitude while preserving direction.
    ///
    /// Negative lengths reverse the vector, matching the force calculations
    /// used in The Nature of Code. This method corresponds to
    /// [p5.js `setMag()`](https://p5js.org/reference/p5.Vector/setMag/).
    @discardableResult
    mutating func setMag(_ length: CGFloat) -> Self {
        precondition(length.isFinite)
        normalize()
        mult(length)
        return self
    }

    /// Returns the clockwise two-dimensional angle from the positive x-axis.
    ///
    /// The result is in radians. This method corresponds to
    /// [p5.js `heading()`](https://p5js.org/reference/p5.Vector/heading/).
    func heading() -> CGFloat {
        atan2(y, x)
    }

    /// Returns the two-dimensional heading in an explicit angle mode.
    func heading(angleMode: P5AngleMode) -> CGFloat {
        angleMode.value(fromRadians: heading())
    }

    /// Rotates the x and y components to a heading while preserving their
    /// two-dimensional magnitude and the z component.
    ///
    /// The angle is in radians. This method corresponds to
    /// [p5.js `setHeading()`](https://p5js.org/reference/p5.Vector/setHeading/).
    @discardableResult
    mutating func setHeading(_ angle: CGFloat) -> Self {
        precondition(angle.isFinite)
        let magnitude2D = ((x * x) + (y * y)).squareRoot()
        x = cos(angle) * magnitude2D
        y = sin(angle) * magnitude2D
        return self
    }

    /// Rotates to a heading expressed in an explicit angle mode.
    @discardableResult
    mutating func setHeading(_ angle: CGFloat, angleMode: P5AngleMode) -> Self {
        setHeading(angleMode.radians(from: angle))
    }

    /// Rotates the x and y components by an angle in radians.
    ///
    /// This method corresponds to
    /// [p5.js `rotate()`](https://p5js.org/reference/p5.Vector/rotate/).
    @discardableResult
    mutating func rotate(_ angle: CGFloat) -> Self {
        precondition(angle.isFinite)
        let originalX = x
        let originalY = y
        x = (originalX * cos(angle)) - (originalY * sin(angle))
        y = (originalX * sin(angle)) + (originalY * cos(angle))
        return self
    }

    /// Rotates by an angle expressed in an explicit angle mode.
    @discardableResult
    mutating func rotate(_ angle: CGFloat, angleMode: P5AngleMode) -> Self {
        rotate(angleMode.radians(from: angle))
    }

    /// Returns the signed two-dimensional angle to another vector in radians.
    ///
    /// This method corresponds to
    /// [p5.js `angleBetween()`](https://p5js.org/reference/p5.Vector/angleBetween/).
    func angleBetween(_ other: Self) -> CGFloat {
        let crossZ = (x * other.y) - (y * other.x)
        let dot2D = (x * other.x) + (y * other.y)
        return atan2(crossZ, dot2D)
    }

    /// Returns the signed angle to another vector in an explicit angle mode.
    func angleBetween(_ other: Self, angleMode: P5AngleMode) -> CGFloat {
        angleMode.value(fromRadians: angleBetween(other))
    }

    /// Reflects the vector from a surface normal.
    ///
    /// A zero normal leaves the vector unchanged. Nonzero normals are normalized
    /// before reflection.
    @discardableResult
    mutating func reflect(_ normal: Self) -> Self {
        var unitNormal = normal
        guard unitNormal.magSq() != 0 else {
            return self
        }
        unitNormal.normalize()
        self -= unitNormal * (2 * dot(unitNormal))
        return self
    }

    /// Moves the components proportionally toward another vector.
    ///
    /// This method corresponds to
    /// [p5.js `lerp()`](https://p5js.org/reference/p5.Vector/lerp/).
    @discardableResult
    mutating func lerp(_ other: Self, _ amount: CGFloat) -> Self {
        x += (other.x - x) * amount
        y += (other.y - y) * amount
        z += (other.z - z) * amount
        return self
    }

    /// Spherically interpolates direction and linearly interpolates magnitude.
    ///
    /// Opposite vectors follow a deterministic orthogonal arc. A zero endpoint
    /// falls back to linear interpolation because its direction is undefined.
    @discardableResult
    mutating func slerp(_ other: Self, _ amount: CGFloat) -> Self {
        precondition(amount.isFinite)
        let startMagnitude = mag()
        let stopMagnitude = other.mag()
        guard startMagnitude != 0 && stopMagnitude != 0 else {
            return lerp(other, amount)
        }

        let start = self / startMagnitude
        let stop = other / stopMagnitude
        let cosine = min(max(start.dot(stop), -1), 1)
        let direction: Self
        if cosine > 0.9995 {
            direction = Self.normalize(Self.lerp(start, stop, amount))
        } else if cosine < -0.9995 {
            let axis = abs(start.x) < 0.9 ? Self(x: 1) : Self(y: 1)
            let orthogonal = Self.normalize(start.cross(axis))
            direction = (start * cos(.pi * amount)) + (orthogonal * sin(.pi * amount))
        } else {
            let angle = acos(cosine) * amount
            let relative = Self.normalize(stop - (start * cosine))
            direction = (start * cos(angle)) + (relative * sin(angle))
        }
        self = direction * P5Math.lerp(startMagnitude, stopMagnitude, amount)
        return self
    }

    /// Returns the distance between two vectors.
    static func dist(_ lhs: Self, _ rhs: Self) -> CGFloat {
        lhs.dist(rhs)
    }

    /// Returns a normalized copy of a vector.
    static func normalize(_ vector: Self) -> Self {
        var result = vector
        result.normalize()
        return result
    }

    /// Returns a copy limited to a maximum magnitude.
    static func limit(_ vector: Self, _ maximum: CGFloat) -> Self {
        var result = vector
        result.limit(maximum)
        return result
    }

    /// Returns a copy with a new magnitude.
    static func setMag(_ vector: Self, _ length: CGFloat) -> Self {
        var result = vector
        result.setMag(length)
        return result
    }

    /// Returns the signed two-dimensional angle between two vectors.
    static func angleBetween(_ lhs: Self, _ rhs: Self) -> CGFloat {
        lhs.angleBetween(rhs)
    }

    /// Returns an interpolated copy without changing either input.
    static func lerp(_ lhs: Self, _ rhs: Self, _ amount: CGFloat) -> Self {
        var result = lhs
        result.lerp(rhs, amount)
        return result
    }

    /// Returns the reflection of a vector from a surface normal.
    static func reflect(_ vector: Self, normal: Self) -> Self {
        var result = vector
        result.reflect(normal)
        return result
    }

    /// Returns a spherical interpolation without changing either input.
    static func slerp(_ lhs: Self, _ rhs: Self, _ amount: CGFloat) -> Self {
        var result = lhs
        result.slerp(rhs, amount)
        return result
    }
}

// MARK: - Construction

public extension P5Vector {
    /// Creates a two-dimensional vector from an angle and magnitude.
    ///
    /// The angle is always in radians, matching
    /// [p5.js `fromAngle()`](https://p5js.org/reference/p5.Vector/fromAngle/).
    static func fromAngle(_ angle: CGFloat, length: CGFloat = 1) -> Self {
        precondition(angle.isFinite && length.isFinite)
        return Self(x: cos(angle) * length, y: sin(angle) * length)
    }

    /// Creates a two-dimensional vector from an angle in an explicit mode.
    static func fromAngle(
        _ angle: CGFloat,
        length: CGFloat = 1,
        angleMode: P5AngleMode
    ) -> Self {
        fromAngle(angleMode.radians(from: angle), length: length)
    }

    /// Creates a unit vector with a random two-dimensional heading.
    ///
    /// This method corresponds to
    /// [p5.js `random2D()`](https://p5js.org/reference/p5.Vector/random2D/).
    static func random2D() -> Self {
        var generator = SystemRandomNumberGenerator()
        return random2D(using: &generator)
    }

    /// Creates a random two-dimensional unit vector using a supplied generator.
    ///
    /// Supplying a generator is a native Swift extension that enables seeded,
    /// deterministic simulations and tests.
    static func random2D<R: RandomNumberGenerator>(
        using generator: inout R
    ) -> Self {
        let angle = CGFloat.random(in: 0..<2 * .pi, using: &generator)
        return fromAngle(angle)
    }

    /// Creates a random three-dimensional unit vector.
    static func random3D() -> Self {
        var generator = SystemRandomNumberGenerator()
        return random3D(using: &generator)
    }

    /// Creates a random three-dimensional unit vector using a supplied generator.
    static func random3D<R: RandomNumberGenerator>(using generator: inout R) -> Self {
        let z = CGFloat.random(in: -1...1, using: &generator)
        let angle = CGFloat.random(in: 0..<2 * .pi, using: &generator)
        let radius = sqrt(max(0, 1 - (z * z)))
        return Self(x: radius * cos(angle), y: radius * sin(angle), z: z)
    }
}

// MARK: - Swift operators

public extension P5Vector {
    /// Returns a vector with every component negated.
    static prefix func - (value: Self) -> Self {
        Self(x: -value.x, y: -value.y, z: -value.z)
    }

    /// Returns the component-wise sum of two vectors.
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    /// Returns the component-wise difference between two vectors.
    static func - (lhs: Self, rhs: Self) -> Self {
        lhs + -rhs
    }

    /// Returns a vector whose components are multiplied by a finite scalar.
    static func * (lhs: Self, rhs: CGFloat) -> Self {
        precondition(rhs.isFinite)
        return Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    /// Returns a vector whose components are multiplied by a finite scalar.
    static func * (lhs: CGFloat, rhs: Self) -> Self {
        rhs * lhs
    }

    /// Returns a vector whose components are divided by a finite, nonzero scalar.
    static func / (lhs: Self, rhs: CGFloat) -> Self {
        precondition(rhs.isFinite && rhs != 0)
        return lhs * (1 / rhs)
    }

    /// Adds another vector to this vector component by component.
    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    /// Subtracts another vector from this vector component by component.
    static func -= (lhs: inout Self, rhs: Self) {
        lhs = lhs - rhs
    }

    /// Multiplies every component of this vector by a finite scalar.
    static func *= (lhs: inout Self, rhs: CGFloat) {
        lhs = lhs * rhs
    }

    /// Divides every component of this vector by a finite, nonzero scalar.
    static func /= (lhs: inout Self, rhs: CGFloat) {
        lhs = lhs / rhs
    }
}
