import Foundation

/// Failures produced by validated 3D matrices, cameras, and projections.
public enum P5Math3DError: Error, Sendable, Hashable, LocalizedError {
    /// A matrix contains a nonfinite component.
    case nonFiniteMatrix
    /// A projection parameter is nonfinite or outside its supported domain.
    case invalidProjection
    /// Camera position and target coincide, or its up vector is degenerate.
    case invalidCamera

    /// A stable diagnostic for logs and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .nonFiniteMatrix:
            "A 3D matrix component is not finite."
        case .invalidProjection:
            "The 3D projection parameters are invalid."
        case .invalidCamera:
            "The camera position, target, and up vector do not define a view."
        }
    }
}

/// A finite column-major 4-by-4 matrix compatible with Metal's `float4x4` layout.
@frozen
public struct P5Matrix4x4: Sendable, Hashable, Codable {
    /// The first column.
    public let column0: SIMD4<Float>
    /// The second column.
    public let column1: SIMD4<Float>
    /// The third column.
    public let column2: SIMD4<Float>
    /// The fourth column.
    public let column3: SIMD4<Float>

    /// Creates a finite column-major matrix.
    ///
    /// - Precondition: Every component is finite.
    public init(
        column0: SIMD4<Float>,
        column1: SIMD4<Float>,
        column2: SIMD4<Float>,
        column3: SIMD4<Float>
    ) {
        precondition(Self.areFinite([column0, column1, column2, column3]))
        self.column0 = column0
        self.column1 = column1
        self.column2 = column2
        self.column3 = column3
    }

    /// The identity transformation.
    public static let identity = Self(
        column0: SIMD4(1, 0, 0, 0),
        column1: SIMD4(0, 1, 0, 0),
        column2: SIMD4(0, 0, 1, 0),
        column3: SIMD4(0, 0, 0, 1)
    )

    /// Creates a translation matrix.
    public static func translation(x: Float, y: Float, z: Float) -> Self {
        precondition(x.isFinite && y.isFinite && z.isFinite)
        return Self(
            column0: SIMD4(1, 0, 0, 0),
            column1: SIMD4(0, 1, 0, 0),
            column2: SIMD4(0, 0, 1, 0),
            column3: SIMD4(x, y, z, 1)
        )
    }

    /// Creates a nonzero scaling matrix.
    public static func scale(x: Float, y: Float, z: Float) -> Self {
        precondition(x.isFinite && y.isFinite && z.isFinite)
        return Self(
            column0: SIMD4(x, 0, 0, 0),
            column1: SIMD4(0, y, 0, 0),
            column2: SIMD4(0, 0, z, 0),
            column3: SIMD4(0, 0, 0, 1)
        )
    }

    /// Creates a right-handed x-axis rotation matrix.
    public static func rotationX(_ radians: Float) -> Self {
        precondition(radians.isFinite)
        let cosine = cos(radians)
        let sine = sin(radians)
        return Self(
            column0: SIMD4(1, 0, 0, 0),
            column1: SIMD4(0, cosine, sine, 0),
            column2: SIMD4(0, -sine, cosine, 0),
            column3: SIMD4(0, 0, 0, 1)
        )
    }

    /// Creates a right-handed y-axis rotation matrix.
    public static func rotationY(_ radians: Float) -> Self {
        precondition(radians.isFinite)
        let cosine = cos(radians)
        let sine = sin(radians)
        return Self(
            column0: SIMD4(cosine, 0, -sine, 0),
            column1: SIMD4(0, 1, 0, 0),
            column2: SIMD4(sine, 0, cosine, 0),
            column3: SIMD4(0, 0, 0, 1)
        )
    }

    /// Creates a right-handed z-axis rotation matrix.
    public static func rotationZ(_ radians: Float) -> Self {
        precondition(radians.isFinite)
        let cosine = cos(radians)
        let sine = sin(radians)
        return Self(
            column0: SIMD4(cosine, sine, 0, 0),
            column1: SIMD4(-sine, cosine, 0, 0),
            column2: SIMD4(0, 0, 1, 0),
            column3: SIMD4(0, 0, 0, 1)
        )
    }

    /// Reads one row and column using zero-based indices.
    ///
    /// - Precondition: Both indices are in `0..<4`.
    public subscript(row: Int, column: Int) -> Float {
        precondition((0..<4).contains(row) && (0..<4).contains(column))
        return columns[column][row]
    }

    /// The matrix with rows and columns exchanged.
    public var transposed: Self {
        Self(
            column0: SIMD4(column0.x, column1.x, column2.x, column3.x),
            column1: SIMD4(column0.y, column1.y, column2.y, column3.y),
            column2: SIMD4(column0.z, column1.z, column2.z, column3.z),
            column3: SIMD4(column0.w, column1.w, column2.w, column3.w)
        )
    }

    /// Transforms a point and performs homogeneous division when required.
    public func transformPoint(_ point: P5Vector) -> P5Vector {
        let value = multiplied(
            by: SIMD4(Float(point.x), Float(point.y), Float(point.z), 1)
        )
        let divisor = value.w == 0 ? 1 : value.w
        return P5Vector(
            x: CGFloat(value.x / divisor),
            y: CGFloat(value.y / divisor),
            z: CGFloat(value.z / divisor)
        )
    }

    /// Transforms a direction without applying translation.
    public func transformDirection(_ direction: P5Vector) -> P5Vector {
        let value = multiplied(
            by: SIMD4(Float(direction.x), Float(direction.y), Float(direction.z), 0)
        )
        return P5Vector(x: CGFloat(value.x), y: CGFloat(value.y), z: CGFloat(value.z))
    }

    /// Multiplies two transformations using column-vector convention.
    public static func * (lhs: Self, rhs: Self) -> Self {
        Self(
            column0: lhs.multiplied(by: rhs.column0),
            column1: lhs.multiplied(by: rhs.column1),
            column2: lhs.multiplied(by: rhs.column2),
            column3: lhs.multiplied(by: rhs.column3)
        )
    }

    /// Decodes only finite matrices.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let columns = [
            try container.decode(SIMD4<Float>.self, forKey: .column0),
            try container.decode(SIMD4<Float>.self, forKey: .column1),
            try container.decode(SIMD4<Float>.self, forKey: .column2),
            try container.decode(SIMD4<Float>.self, forKey: .column3),
        ]
        guard Self.areFinite(columns) else { throw P5Math3DError.nonFiniteMatrix }
        column0 = columns[0]
        column1 = columns[1]
        column2 = columns[2]
        column3 = columns[3]
    }

    private var columns: [SIMD4<Float>] {
        [column0, column1, column2, column3]
    }

    private func multiplied(by vector: SIMD4<Float>) -> SIMD4<Float> {
        (column0 * vector.x) + (column1 * vector.y) + (column2 * vector.z)
            + (column3 * vector.w)
    }

    private static func areFinite(_ columns: [SIMD4<Float>]) -> Bool {
        columns.allSatisfy { column in
            column.x.isFinite && column.y.isFinite && column.z.isFinite && column.w.isFinite
        }
    }
}

/// A right-handed Metal projection with normalized depth in `0...1`.
public enum P5Projection3D: Sendable, Hashable, Codable {
    /// A perspective projection described by vertical field of view and clipping planes.
    case perspective(verticalFieldOfView: Float, near: Float, far: Float)
    /// An orthographic projection described by visible height and clipping planes.
    case orthographic(height: Float, near: Float, far: Float)

    /// Builds a projection matrix for a positive viewport aspect ratio.
    public func matrix(aspectRatio: Float) throws -> P5Matrix4x4 {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            throw P5Math3DError.invalidProjection
        }
        switch self {
        case .perspective(let fieldOfView, let near, let far):
            guard
                fieldOfView.isFinite, fieldOfView > 0, fieldOfView < .pi,
                near.isFinite, near > 0, far.isFinite, far > near
            else { throw P5Math3DError.invalidProjection }
            let yScale = 1 / tan(fieldOfView / 2)
            let xScale = yScale / aspectRatio
            let zScale = far / (near - far)
            return P5Matrix4x4(
                column0: SIMD4(xScale, 0, 0, 0),
                column1: SIMD4(0, yScale, 0, 0),
                column2: SIMD4(0, 0, zScale, -1),
                column3: SIMD4(0, 0, near * zScale, 0)
            )
        case .orthographic(let height, let near, let far):
            guard
                height.isFinite, height > 0, near.isFinite, far.isFinite, far > near
            else { throw P5Math3DError.invalidProjection }
            let width = height * aspectRatio
            return P5Matrix4x4(
                column0: SIMD4(2 / width, 0, 0, 0),
                column1: SIMD4(0, 2 / height, 0, 0),
                column2: SIMD4(0, 0, 1 / (near - far), 0),
                column3: SIMD4(0, 0, near / (near - far), 1)
            )
        }
    }
}

/// An immutable right-handed camera looking toward its target along negative view z.
public struct P5Camera3D: Sendable, Hashable, Codable {
    /// Camera position in world coordinates.
    public let position: P5Vector
    /// Point observed by the camera.
    public let target: P5Vector
    /// Approximate world-up direction.
    public let up: P5Vector
    /// Projection applied after the view transform.
    public let projection: P5Projection3D

    /// Creates a validated camera.
    public init(
        position: P5Vector = P5Vector(x: 0, y: 0, z: 5),
        target: P5Vector = .zero,
        up: P5Vector = P5Vector(x: 0, y: 1, z: 0),
        projection: P5Projection3D = .perspective(
            verticalFieldOfView: .pi / 3,
            near: 0.1,
            far: 1_000
        )
    ) throws {
        guard Self.isValid(position: position, target: target, up: up) else {
            throw P5Math3DError.invalidCamera
        }
        self.position = position
        self.target = target
        self.up = up
        self.projection = projection
    }

    /// The world-to-view transformation.
    public var viewMatrix: P5Matrix4x4 {
        let eye = position.float3
        let forward = Self.normalized(target.float3 - eye)
        let right = Self.normalized(Self.cross(forward, up.float3))
        let correctedUp = Self.cross(right, forward)
        return P5Matrix4x4(
            column0: SIMD4(right.x, correctedUp.x, -forward.x, 0),
            column1: SIMD4(right.y, correctedUp.y, -forward.y, 0),
            column2: SIMD4(right.z, correctedUp.z, -forward.z, 0),
            column3: SIMD4(
                -Self.dot(right, eye),
                -Self.dot(correctedUp, eye),
                Self.dot(forward, eye),
                1
            )
        )
    }

    /// Decodes while preserving camera invariants.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            position: container.decode(P5Vector.self, forKey: .position),
            target: container.decode(P5Vector.self, forKey: .target),
            up: container.decode(P5Vector.self, forKey: .up),
            projection: container.decode(P5Projection3D.self, forKey: .projection)
        )
    }

    private static func isValid(position: P5Vector, target: P5Vector, up: P5Vector) -> Bool {
        let values = position.array() + target.array() + up.array()
        guard values.allSatisfy(\.isFinite) else { return false }
        let forward = target.float3 - position.float3
        return lengthSquared(forward) > 0 && lengthSquared(cross(forward, up.float3)) > 0
    }

    private static func normalized(_ value: SIMD3<Float>) -> SIMD3<Float> {
        value / sqrt(lengthSquared(value))
    }

    private static func lengthSquared(_ value: SIMD3<Float>) -> Float {
        dot(value, value)
    }

    private static func dot(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
        (lhs.x * rhs.x) + (lhs.y * rhs.y) + (lhs.z * rhs.z)
    }

    private static func cross(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            (lhs.y * rhs.z) - (lhs.z * rhs.y),
            (lhs.z * rhs.x) - (lhs.x * rhs.z),
            (lhs.x * rhs.y) - (lhs.y * rhs.x)
        )
    }
}

extension P5Vector {
    fileprivate var float3: SIMD3<Float> {
        SIMD3(Float(x), Float(y), Float(z))
    }
}
