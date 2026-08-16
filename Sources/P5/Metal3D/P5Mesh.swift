import Foundation

/// Failures produced while constructing validated 3D geometry.
public enum P5MeshError: Error, Sendable, Hashable, LocalizedError {
    /// A mesh needs at least three vertices and one triangle.
    case empty
    /// A vertex contains a nonfinite position, normal, or texture coordinate.
    case invalidVertex(Int)
    /// Triangle indices are not arranged in groups of three.
    case invalidIndexCount
    /// An index points beyond the vertex array.
    case indexOutOfBounds(UInt32)
    /// A triangle has zero area and cannot produce a normal.
    case degenerateTriangle(Int)
    /// A primitive dimension is nonfinite or not greater than zero.
    case invalidDimension
    /// A curved primitive has too few longitudinal or latitudinal segments.
    case insufficientSegments

    /// A stable diagnostic for logs and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .empty:
            "A 3D mesh requires at least three vertices and one triangle."
        case .invalidVertex(let index):
            "3D mesh vertex \(index) contains a nonfinite component."
        case .invalidIndexCount:
            "3D mesh indices must describe complete triangles."
        case .indexOutOfBounds(let index):
            "3D mesh index \(index) is outside the vertex array."
        case .degenerateTriangle(let triangle):
            "3D mesh triangle \(triangle) has zero area."
        case .invalidDimension:
            "A 3D primitive dimension must be finite and greater than zero."
        case .insufficientSegments:
            "The 3D primitive does not have enough segments."
        }
    }
}

/// A normalized two-dimensional texture coordinate.
@frozen
public struct P5TextureCoordinate: Sendable, Hashable, Codable {
    /// Horizontal coordinate, normally in `0...1`.
    public var u: Float
    /// Vertical coordinate, normally in `0...1`.
    public var v: Float

    /// Creates a texture coordinate.
    ///
    /// Tiling values outside `0...1` are allowed.
    public init(u: Float = 0, v: Float = 0) {
        self.u = u
        self.v = v
    }
}

/// One position, normal, texture coordinate, and vertex color in a 3D mesh.
@frozen
public struct P5Vertex3D: Sendable, Hashable, Codable {
    /// Position in model coordinates.
    public var position: P5Vector
    /// Surface normal in model coordinates.
    public var normal: P5Vector
    /// Texture coordinate.
    public var textureCoordinate: P5TextureCoordinate
    /// Linear red, green, blue, and alpha multipliers.
    public var color: SIMD4<Float>

    /// Creates a vertex. ``P5Mesh`` validates all components before accepting it.
    public init(
        position: P5Vector,
        normal: P5Vector = .zero,
        textureCoordinate: P5TextureCoordinate = P5TextureCoordinate(),
        color: SIMD4<Float> = SIMD4(repeating: 1)
    ) {
        self.position = position
        self.normal = normal
        self.textureCoordinate = textureCoordinate
        self.color = color
    }
}

/// Axis-aligned model-space bounds for a 3D mesh.
@frozen
public struct P5Bounds3D: Sendable, Hashable, Codable {
    /// Minimum x, y, and z components.
    public let minimum: P5Vector
    /// Maximum x, y, and z components.
    public let maximum: P5Vector

    /// Creates ordered finite bounds.
    ///
    /// - Precondition: Both endpoints are finite and minimum does not exceed maximum.
    public init(minimum: P5Vector, maximum: P5Vector) {
        precondition(Self.isValid(minimum: minimum, maximum: maximum))
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Midpoint of the bounds.
    public var center: P5Vector { (minimum + maximum) / 2 }

    /// Width, height, and depth of the bounds.
    public var size: P5Vector { maximum - minimum }

    /// Decodes only ordered finite bounds.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let minimum = try container.decode(P5Vector.self, forKey: .minimum)
        let maximum = try container.decode(P5Vector.self, forKey: .maximum)
        guard Self.isValid(minimum: minimum, maximum: maximum) else {
            throw P5MeshError.invalidDimension
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    private static func isValid(minimum: P5Vector, maximum: P5Vector) -> Bool {
        (minimum.array() + maximum.array()).allSatisfy(\.isFinite)
            && minimum.x <= maximum.x && minimum.y <= maximum.y && minimum.z <= maximum.z
    }
}

/// Validated indexed triangle geometry independent of a rendering backend.
@frozen
public struct P5Mesh: Sendable, Hashable, Codable {
    /// Model-space vertices.
    public let vertices: [P5Vertex3D]
    /// Zero-based triangle indices in counterclockwise winding order.
    public let indices: [UInt32]

    /// Creates a validated indexed triangle mesh.
    public init(vertices: [P5Vertex3D], indices: [UInt32]) throws {
        guard vertices.count >= 3, indices.isEmpty == false else { throw P5MeshError.empty }
        guard indices.count.isMultiple(of: 3) else { throw P5MeshError.invalidIndexCount }
        for (index, vertex) in vertices.enumerated() where Self.isFinite(vertex) == false {
            throw P5MeshError.invalidVertex(index)
        }
        if let invalid = indices.first(where: { Int($0) >= vertices.count }) {
            throw P5MeshError.indexOutOfBounds(invalid)
        }
        self.vertices = vertices
        self.indices = indices
    }

    /// Axis-aligned bounds enclosing every vertex.
    public var bounds: P5Bounds3D {
        var minimum = vertices[0].position
        var maximum = minimum
        for vertex in vertices.dropFirst() {
            minimum.x = Swift.min(minimum.x, vertex.position.x)
            minimum.y = Swift.min(minimum.y, vertex.position.y)
            minimum.z = Swift.min(minimum.z, vertex.position.z)
            maximum.x = Swift.max(maximum.x, vertex.position.x)
            maximum.y = Swift.max(maximum.y, vertex.position.y)
            maximum.z = Swift.max(maximum.z, vertex.position.z)
        }
        return P5Bounds3D(minimum: minimum, maximum: maximum)
    }

    /// Returns a copy with smooth area-weighted normals calculated from its triangles.
    public func calculatingNormals() throws -> Self {
        var accumulated = Array(repeating: SIMD3<Float>.zero, count: vertices.count)
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let first = Int(indices[offset])
            let second = Int(indices[offset + 1])
            let third = Int(indices[offset + 2])
            let a = vertices[first].position.float3ForMesh
            let b = vertices[second].position.float3ForMesh
            let c = vertices[third].position.float3ForMesh
            let normal = Self.cross(b - a, c - a)
            guard Self.lengthSquared(normal) > 0 else {
                throw P5MeshError.degenerateTriangle(offset / 3)
            }
            accumulated[first] += normal
            accumulated[second] += normal
            accumulated[third] += normal
        }
        var result = vertices
        for index in result.indices {
            let normal = accumulated[index]
            guard Self.lengthSquared(normal) > 0 else {
                throw P5MeshError.invalidVertex(index)
            }
            let normalized = normal / sqrt(Self.lengthSquared(normal))
            result[index].normal = P5Vector(
                x: CGFloat(normalized.x),
                y: CGFloat(normalized.y),
                z: CGFloat(normalized.z)
            )
        }
        return try Self(vertices: result, indices: indices)
    }

    /// Creates a counterclockwise plane centered at the origin in the xy plane.
    public static func plane(width: Float = 1, height: Float = 1) throws -> Self {
        guard Self.validDimensions([width, height]) else { throw P5MeshError.invalidDimension }
        let x = CGFloat(width / 2)
        let y = CGFloat(height / 2)
        let normal = P5Vector(x: 0, y: 0, z: 1)
        return try Self(
            vertices: [
                P5Vertex3D(
                    position: P5Vector(x: -x, y: -y),
                    normal: normal,
                    textureCoordinate: P5TextureCoordinate(u: 0, v: 1)
                ),
                P5Vertex3D(
                    position: P5Vector(x: x, y: -y),
                    normal: normal,
                    textureCoordinate: P5TextureCoordinate(u: 1, v: 1)
                ),
                P5Vertex3D(
                    position: P5Vector(x: x, y: y),
                    normal: normal,
                    textureCoordinate: P5TextureCoordinate(u: 1, v: 0)
                ),
                P5Vertex3D(
                    position: P5Vector(x: -x, y: y),
                    normal: normal,
                    textureCoordinate: P5TextureCoordinate(u: 0, v: 0)
                ),
            ],
            indices: [0, 1, 2, 0, 2, 3]
        )
    }

    /// Creates a box centered at the origin with independent face normals.
    public static func box(width: Float = 1, height: Float = 1, depth: Float = 1) throws
        -> Self
    {
        guard Self.validDimensions([width, height, depth]) else {
            throw P5MeshError.invalidDimension
        }
        let x = CGFloat(width / 2)
        let y = CGFloat(height / 2)
        let z = CGFloat(depth / 2)
        let faces: [(P5Vector, [P5Vector])] = [
            (
                P5Vector(x: 0, y: 0, z: 1),
                [
                    P5Vector(x: -x, y: -y, z: z), P5Vector(x: x, y: -y, z: z),
                    P5Vector(x: x, y: y, z: z), P5Vector(x: -x, y: y, z: z),
                ]
            ),
            (
                P5Vector(x: 0, y: 0, z: -1),
                [
                    P5Vector(x: x, y: -y, z: -z), P5Vector(x: -x, y: -y, z: -z),
                    P5Vector(x: -x, y: y, z: -z), P5Vector(x: x, y: y, z: -z),
                ]
            ),
            (
                P5Vector(x: 1, y: 0, z: 0),
                [
                    P5Vector(x: x, y: -y, z: z), P5Vector(x: x, y: -y, z: -z),
                    P5Vector(x: x, y: y, z: -z), P5Vector(x: x, y: y, z: z),
                ]
            ),
            (
                P5Vector(x: -1, y: 0, z: 0),
                [
                    P5Vector(x: -x, y: -y, z: -z), P5Vector(x: -x, y: -y, z: z),
                    P5Vector(x: -x, y: y, z: z), P5Vector(x: -x, y: y, z: -z),
                ]
            ),
            (
                P5Vector(x: 0, y: 1, z: 0),
                [
                    P5Vector(x: -x, y: y, z: z), P5Vector(x: x, y: y, z: z),
                    P5Vector(x: x, y: y, z: -z), P5Vector(x: -x, y: y, z: -z),
                ]
            ),
            (
                P5Vector(x: 0, y: -1, z: 0),
                [
                    P5Vector(x: -x, y: -y, z: -z), P5Vector(x: x, y: -y, z: -z),
                    P5Vector(x: x, y: -y, z: z), P5Vector(x: -x, y: -y, z: z),
                ]
            ),
        ]
        let textureCoordinates = [
            P5TextureCoordinate(u: 0, v: 1), P5TextureCoordinate(u: 1, v: 1),
            P5TextureCoordinate(u: 1, v: 0), P5TextureCoordinate(u: 0, v: 0),
        ]
        var vertices: [P5Vertex3D] = []
        var indices: [UInt32] = []
        for (faceIndex, face) in faces.enumerated() {
            let base = UInt32(faceIndex * 4)
            vertices += zip(face.1, textureCoordinates).map {
                P5Vertex3D(position: $0.0, normal: face.0, textureCoordinate: $0.1)
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return try Self(vertices: vertices, indices: indices)
    }

    /// Creates a UV sphere centered at the origin.
    public static func sphere(radius: Float = 0.5, segments: Int = 24, rings: Int = 16)
        throws -> Self
    {
        guard Self.validDimensions([radius]) else { throw P5MeshError.invalidDimension }
        guard segments >= 3, rings >= 2 else { throw P5MeshError.insufficientSegments }
        var vertices: [P5Vertex3D] = []
        for ring in 0...rings {
            let v = Float(ring) / Float(rings)
            let latitude = Float.pi * v
            for segment in 0...segments {
                let u = Float(segment) / Float(segments)
                let longitude = Float.pi * 2 * u
                let normal = SIMD3(
                    sin(latitude) * cos(longitude),
                    cos(latitude),
                    sin(latitude) * sin(longitude)
                )
                vertices.append(
                    P5Vertex3D(
                        position: P5Vector(
                            x: CGFloat(normal.x * radius),
                            y: CGFloat(normal.y * radius),
                            z: CGFloat(normal.z * radius)
                        ),
                        normal: P5Vector(
                            x: CGFloat(normal.x), y: CGFloat(normal.y), z: CGFloat(normal.z)
                        ),
                        textureCoordinate: P5TextureCoordinate(u: u, v: v)
                    )
                )
            }
        }
        var indices: [UInt32] = []
        let rowWidth = segments + 1
        for ring in 0..<rings {
            for segment in 0..<segments {
                let first = UInt32((ring * rowWidth) + segment)
                let second = first + UInt32(rowWidth)
                indices += [first, second, first + 1, first + 1, second, second + 1]
            }
        }
        return try Self(vertices: vertices, indices: indices)
    }

    /// Decodes only structurally valid geometry.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            vertices: container.decode([P5Vertex3D].self, forKey: .vertices),
            indices: container.decode([UInt32].self, forKey: .indices)
        )
    }

    private static func validDimensions(_ values: [Float]) -> Bool {
        values.allSatisfy { $0.isFinite && $0 > 0 }
    }

    private static func isFinite(_ vertex: P5Vertex3D) -> Bool {
        let vectorValues = vertex.position.array() + vertex.normal.array()
        return vectorValues.allSatisfy(\.isFinite) && vertex.textureCoordinate.u.isFinite
            && vertex.textureCoordinate.v.isFinite && vertex.color.x.isFinite
            && vertex.color.y.isFinite && vertex.color.z.isFinite && vertex.color.w.isFinite
    }

    private static func cross(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            (lhs.y * rhs.z) - (lhs.z * rhs.y),
            (lhs.z * rhs.x) - (lhs.x * rhs.z),
            (lhs.x * rhs.y) - (lhs.y * rhs.x)
        )
    }

    private static func lengthSquared(_ value: SIMD3<Float>) -> Float {
        (value.x * value.x) + (value.y * value.y) + (value.z * value.z)
    }
}

extension P5Vector {
    fileprivate var float3ForMesh: SIMD3<Float> {
        SIMD3(Float(x), Float(y), Float(z))
    }
}
