import Foundation

/// Failures produced while loading or parsing Wavefront OBJ geometry.
public enum P5Model3DError: Error, Sendable, Hashable, LocalizedError {
    /// Local or remote bytes could not be loaded.
    case loadingFailed(String)
    /// A remote server returned a non-success HTTP status.
    case invalidHTTPStatus(Int)
    /// OBJ bytes are not valid UTF-8 text.
    case invalidTextEncoding
    /// A statement is malformed or references unavailable data.
    case malformed(line: Int, reason: String)
    /// The file uses a geometry statement this loader does not support.
    case unsupportedStatement(line: Int, keyword: String)
    /// Parsed geometry violates a mesh invariant.
    case invalidMesh(P5MeshError)

    /// A stable diagnostic for logs and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .loadingFailed(let reason):
            "The 3D model could not be loaded: \(reason)"
        case .invalidHTTPStatus(let status):
            "The 3D model server returned HTTP status \(status)."
        case .invalidTextEncoding:
            "The 3D model is not valid UTF-8 text."
        case .malformed(let line, let reason):
            "The 3D model is malformed at line \(line): \(reason)"
        case .unsupportedStatement(let line, let keyword):
            "The 3D model uses unsupported statement '\(keyword)' at line \(line)."
        case .invalidMesh(let error):
            error.localizedDescription
        }
    }
}

/// Cancellation-aware loader for validated triangular Wavefront OBJ meshes.
public struct P5OBJModelLoader: Sendable {
    private let runtime: P5OBJLoadingRuntime

    /// Creates a loader using native file reads and the supplied URL session.
    public init(session: URLSession = .shared) {
        runtime = P5OBJLoadingRuntime(session: session)
    }

    init(runtime: P5OBJLoadingRuntime) {
        self.runtime = runtime
    }

    /// Loads a local file URL or remote HTTP(S) URL and parses one mesh.
    public func load(from url: URL) async throws -> P5Mesh {
        try Task.checkCancellation()
        let data: Data
        do {
            if url.isFileURL {
                data = try await runtime.localData(url)
            } else {
                let result = try await runtime.remoteData(url)
                if let response = result.1 as? HTTPURLResponse,
                    (200...299).contains(response.statusCode) == false
                {
                    throw P5Model3DError.invalidHTTPStatus(response.statusCode)
                }
                data = result.0
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as P5Model3DError {
            throw error
        } catch {
            throw P5Model3DError.loadingFailed(error.localizedDescription)
        }
        return try parse(data)
    }

    /// Parses UTF-8 OBJ bytes.
    public func parse(_ data: Data) throws -> P5Mesh {
        guard let source = String(data: data, encoding: .utf8) else {
            throw P5Model3DError.invalidTextEncoding
        }
        return try parse(source)
    }

    /// Parses positions, texture coordinates, normals, and polygon faces.
    ///
    /// Polygon faces are fan-triangulated. Positive and negative OBJ indices are
    /// supported. Missing normals are generated after parsing.
    public func parse(_ source: String) throws -> P5Mesh {
        var positions: [P5Vector] = []
        var textureCoordinates: [P5TextureCoordinate] = []
        var normals: [P5Vector] = []
        var vertices: [P5Vertex3D] = []
        var indices: [UInt32] = []
        var vertexIndices: [OBJReference: UInt32] = [:]
        var hasMissingNormals = false

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let withoutComment = rawLine.prefix { $0 != "#" }
            let fields = withoutComment.split(whereSeparator: \.isWhitespace)
            guard let keyword = fields.first else { continue }
            switch keyword {
            case "v":
                guard fields.count == 4 else {
                    throw Self.malformed(lineNumber, "A vertex position requires x, y, and z.")
                }
                positions.append(
                    P5Vector(
                        x: CGFloat(try Self.float(fields[1], line: lineNumber)),
                        y: CGFloat(try Self.float(fields[2], line: lineNumber)),
                        z: CGFloat(try Self.float(fields[3], line: lineNumber))
                    )
                )
            case "vt":
                guard fields.count >= 3, fields.count <= 4 else {
                    throw Self.malformed(lineNumber, "A texture coordinate requires u and v.")
                }
                textureCoordinates.append(
                    P5TextureCoordinate(
                        u: try Self.float(fields[1], line: lineNumber),
                        v: try Self.float(fields[2], line: lineNumber)
                    )
                )
            case "vn":
                guard fields.count == 4 else {
                    throw Self.malformed(lineNumber, "A normal requires x, y, and z.")
                }
                let normal = SIMD3(
                    try Self.float(fields[1], line: lineNumber),
                    try Self.float(fields[2], line: lineNumber),
                    try Self.float(fields[3], line: lineNumber)
                )
                let lengthSquared =
                    (normal.x * normal.x) + (normal.y * normal.y)
                    + (normal.z * normal.z)
                guard lengthSquared > 0 else {
                    throw Self.malformed(lineNumber, "A normal cannot be zero.")
                }
                let unit = normal / sqrt(lengthSquared)
                normals.append(P5Vector(x: CGFloat(unit.x), y: CGFloat(unit.y), z: CGFloat(unit.z)))
            case "f":
                guard fields.count >= 4 else {
                    throw Self.malformed(lineNumber, "A face requires at least three vertices.")
                }
                var face: [UInt32] = []
                for field in fields.dropFirst() {
                    let reference = try Self.reference(
                        field,
                        positions: positions.count,
                        textures: textureCoordinates.count,
                        normals: normals.count,
                        line: lineNumber
                    )
                    if let existing = vertexIndices[reference] {
                        face.append(existing)
                    } else {
                        let vertexIndex = UInt32(vertices.count)
                        let texture =
                            reference.texture.map { textureCoordinates[$0] }
                            ?? P5TextureCoordinate()
                        let normal = reference.normal.map { normals[$0] } ?? .zero
                        hasMissingNormals = hasMissingNormals || reference.normal == nil
                        vertices.append(
                            P5Vertex3D(
                                position: positions[reference.position],
                                normal: normal,
                                textureCoordinate: texture
                            )
                        )
                        vertexIndices[reference] = vertexIndex
                        face.append(vertexIndex)
                    }
                }
                for index in 1..<(face.count - 1) {
                    indices += [face[0], face[index], face[index + 1]]
                }
            case "o", "g", "s", "usemtl", "mtllib":
                continue
            default:
                throw P5Model3DError.unsupportedStatement(
                    line: lineNumber,
                    keyword: String(keyword)
                )
            }
        }

        do {
            let mesh = try P5Mesh(vertices: vertices, indices: indices)
            return hasMissingNormals ? try mesh.calculatingNormals() : mesh
        } catch let error as P5MeshError {
            throw P5Model3DError.invalidMesh(error)
        }
    }

    private static func float(_ field: Substring, line: Int) throws -> Float {
        guard let value = Float(field), value.isFinite else {
            throw malformed(line, "A numeric component is invalid.")
        }
        return value
    }

    private static func reference(
        _ field: Substring,
        positions: Int,
        textures: Int,
        normals: Int,
        line: Int
    ) throws -> OBJReference {
        let components = field.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count), components[0].isEmpty == false else {
            throw malformed(line, "A face vertex reference is invalid.")
        }
        let position = try index(components[0], count: positions, line: line)
        let texture = try optionalIndex(components, offset: 1, count: textures, line: line)
        let normal = try optionalIndex(components, offset: 2, count: normals, line: line)
        return OBJReference(position: position, texture: texture, normal: normal)
    }

    private static func optionalIndex(
        _ components: [Substring],
        offset: Int,
        count: Int,
        line: Int
    ) throws -> Int? {
        guard components.indices.contains(offset), components[offset].isEmpty == false else {
            return nil
        }
        return try index(components[offset], count: count, line: line)
    }

    private static func index(_ field: Substring, count: Int, line: Int) throws -> Int {
        guard let raw = Int(field), raw != 0 else {
            throw malformed(line, "An OBJ index must be a nonzero integer.")
        }
        let resolved = raw > 0 ? raw - 1 : count + raw
        guard (0..<count).contains(resolved) else {
            throw malformed(line, "An OBJ index is outside the available values.")
        }
        return resolved
    }

    private static func malformed(_ line: Int, _ reason: String) -> P5Model3DError {
        .malformed(line: line, reason: reason)
    }
}

private struct OBJReference: Hashable {
    let position: Int
    let texture: Int?
    let normal: Int?
}

struct P5OBJLoadingRuntime: @unchecked Sendable {
    var localData: @Sendable (URL) async throws -> Data
    var remoteData: @Sendable (URL) async throws -> (Data, URLResponse)

    init(session: URLSession) {
        localData = { url in
            try await Task.detached { try Data(contentsOf: url, options: .mappedIfSafe) }.value
        }
        remoteData = { url in try await session.data(from: url) }
    }

    init(
        localData: @escaping @Sendable (URL) async throws -> Data,
        remoteData: @escaping @Sendable (URL) async throws -> (Data, URLResponse)
    ) {
        self.localData = localData
        self.remoteData = remoteData
    }
}
