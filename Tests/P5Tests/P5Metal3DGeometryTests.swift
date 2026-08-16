import Foundation
import Testing

@testable import P5

@Suite("P5 platform-neutral 3D geometry", .serialized)
struct P5Metal3DGeometryTests {
    @Test("Matrices compose, transpose, transform, and serialize")
    func matrices() throws {
        let identity = P5Matrix4x4.identity
        for row in 0..<4 {
            for column in 0..<4 {
                #expect(identity[row, column] == (row == column ? 1 : 0))
            }
        }

        let translation = P5Matrix4x4.translation(x: 2, y: 3, z: 4)
        let scale = P5Matrix4x4.scale(x: 2, y: 3, z: 4)
        let composed = translation * scale
        #expect(composed.transformPoint(P5Vector(x: 1, y: 1, z: 1)) == P5Vector(x: 4, y: 6, z: 8))
        #expect(
            translation.transformDirection(P5Vector(x: 1, y: 2, z: 3))
                == P5Vector(x: 1, y: 2, z: 3)
        )
        #expect(composed.transposed.transposed == composed)

        let halfTurn = Float.pi / 2
        #expect(
            P5Matrix4x4.rotationX(halfTurn)
                .transformDirection(P5Vector(x: 0, y: 1, z: 0)).isApproximately(
                    P5Vector(x: 0, y: 0, z: 1)
                )
        )
        #expect(
            P5Matrix4x4.rotationY(halfTurn)
                .transformDirection(P5Vector(x: 0, y: 0, z: 1)).isApproximately(
                    P5Vector(x: 1, y: 0, z: 0)
                )
        )
        #expect(
            P5Matrix4x4.rotationZ(halfTurn)
                .transformDirection(P5Vector(x: 1, y: 0, z: 0)).isApproximately(
                    P5Vector(x: 0, y: 1, z: 0)
                )
        )

        let zeroW = P5Matrix4x4(
            column0: SIMD4(1, 0, 0, 0),
            column1: SIMD4(0, 1, 0, 0),
            column2: SIMD4(0, 0, 1, 0),
            column3: .zero
        )
        #expect(zeroW.transformPoint(P5Vector(x: 1, y: 2, z: 3)) == P5Vector(x: 1, y: 2, z: 3))

        let encoded = try JSONEncoder().encode(composed)
        #expect(try JSONDecoder().decode(P5Matrix4x4.self, from: encoded) == composed)

        let propertyList: [String: Any] = [
            "column0": [Float.nan, 0, 0, 0],
            "column1": [0, 1, 0, 0],
            "column2": [0, 0, 1, 0],
            "column3": [0, 0, 0, 1],
        ]
        let corrupt = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )
        #expect(throws: P5Math3DError.nonFiniteMatrix) {
            _ = try PropertyListDecoder().decode(P5Matrix4x4.self, from: corrupt)
        }
    }

    @Test("Perspective, orthographic, and camera matrices use Metal conventions")
    func cameras() throws {
        let perspective = P5Projection3D.perspective(
            verticalFieldOfView: .pi / 2,
            near: 0.1,
            far: 100
        )
        let perspectiveMatrix = try perspective.matrix(aspectRatio: 2)
        #expect(perspectiveMatrix[0, 0].isApproximately(0.5))
        #expect(perspectiveMatrix[1, 1].isApproximately(1))
        #expect(perspectiveMatrix[3, 2] == -1)

        let orthographic = P5Projection3D.orthographic(height: 4, near: 0.1, far: 10)
        let orthographicMatrix = try orthographic.matrix(aspectRatio: 2)
        #expect(orthographicMatrix[0, 0] == 0.25)
        #expect(orthographicMatrix[1, 1] == 0.5)

        let camera = try P5Camera3D(projection: perspective)
        #expect(camera.position == P5Vector(x: 0, y: 0, z: 5))
        #expect(camera.target == .zero)
        #expect(camera.up == P5Vector(x: 0, y: 1, z: 0))
        #expect(camera.projection == perspective)
        #expect(camera.viewMatrix.transformPoint(camera.position).isApproximately(.zero))
        #expect(
            try JSONDecoder().decode(P5Camera3D.self, from: JSONEncoder().encode(camera)) == camera)

        let projectionErrors: [P5Projection3D] = [
            .perspective(verticalFieldOfView: .nan, near: 1, far: 2),
            .perspective(verticalFieldOfView: 0, near: 1, far: 2),
            .perspective(verticalFieldOfView: .pi, near: 1, far: 2),
            .perspective(verticalFieldOfView: 1, near: .nan, far: 2),
            .perspective(verticalFieldOfView: 1, near: 0, far: 2),
            .perspective(verticalFieldOfView: 1, near: 1, far: .nan),
            .perspective(verticalFieldOfView: 1, near: 1, far: 1),
            .orthographic(height: .nan, near: 1, far: 2),
            .orthographic(height: 0, near: 1, far: 2),
            .orthographic(height: 1, near: .nan, far: 2),
            .orthographic(height: 1, near: 1, far: .nan),
            .orthographic(height: 1, near: 1, far: 1),
        ]
        for projection in projectionErrors {
            #expect(throws: P5Math3DError.invalidProjection) {
                _ = try projection.matrix(aspectRatio: 1)
            }
        }
        #expect(throws: P5Math3DError.invalidProjection) {
            _ = try perspective.matrix(aspectRatio: .nan)
        }
        #expect(throws: P5Math3DError.invalidProjection) {
            _ = try perspective.matrix(aspectRatio: 0)
        }

        let invalidCameras: [(P5Vector, P5Vector, P5Vector)] = [
            (P5Vector(x: .nan), .zero, P5Vector(x: 0, y: 1)),
            (.zero, .zero, P5Vector(x: 0, y: 1)),
            (.zero, P5Vector(x: 0, y: 0, z: -1), .zero),
            (.zero, P5Vector(x: 0, y: 0, z: -1), P5Vector(x: 0, y: 0, z: 2)),
        ]
        for values in invalidCameras {
            #expect(throws: P5Math3DError.invalidCamera) {
                _ = try P5Camera3D(position: values.0, target: values.1, up: values.2)
            }
        }

        var cameraObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(camera)) as? [String: Any]
        )
        cameraObject["target"] = cameraObject["position"]
        let invalidCameraData = try JSONSerialization.data(withJSONObject: cameraObject)
        #expect(throws: P5Math3DError.invalidCamera) {
            _ = try JSONDecoder().decode(P5Camera3D.self, from: invalidCameraData)
        }

        for error in [
            P5Math3DError.nonFiniteMatrix,
            .invalidProjection,
            .invalidCamera,
        ] {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Meshes validate, bound, generate normals, and round-trip")
    func meshes() throws {
        var textureCoordinate = P5TextureCoordinate()
        textureCoordinate.u = 2
        textureCoordinate.v = -1
        #expect(textureCoordinate == P5TextureCoordinate(u: 2, v: -1))

        var vertex = P5Vertex3D(position: .zero)
        vertex.position = P5Vector(x: 1)
        vertex.normal = P5Vector(y: 1)
        vertex.textureCoordinate = textureCoordinate
        vertex.color = SIMD4(1, 0, 0, 1)
        #expect(
            try JSONDecoder().decode(P5Vertex3D.self, from: JSONEncoder().encode(vertex)) == vertex)

        let vertices = [
            P5Vertex3D(position: P5Vector(x: -1, y: -1)),
            P5Vertex3D(position: P5Vector(x: 1, y: -1)),
            P5Vertex3D(position: P5Vector(x: 0, y: 1)),
        ]
        let mesh = try P5Mesh(vertices: vertices, indices: [0, 1, 2])
        #expect(mesh.vertices == vertices)
        #expect(mesh.indices == [0, 1, 2])
        #expect(mesh.bounds.minimum == P5Vector(x: -1, y: -1))
        #expect(mesh.bounds.maximum == P5Vector(x: 1, y: 1))
        #expect(mesh.bounds.center == .zero)
        #expect(mesh.bounds.size == P5Vector(x: 2, y: 2))

        let normalMesh = try mesh.calculatingNormals()
        #expect(normalMesh.vertices.allSatisfy { $0.normal == P5Vector(x: 0, y: 0, z: 1) })
        #expect(try JSONDecoder().decode(P5Mesh.self, from: JSONEncoder().encode(mesh)) == mesh)
        #expect(
            try JSONDecoder().decode(P5Bounds3D.self, from: JSONEncoder().encode(mesh.bounds))
                == mesh.bounds
        )

        #expect(throws: P5MeshError.empty) { _ = try P5Mesh(vertices: [], indices: []) }
        #expect(throws: P5MeshError.empty) { _ = try P5Mesh(vertices: vertices, indices: []) }
        #expect(throws: P5MeshError.invalidIndexCount) {
            _ = try P5Mesh(vertices: vertices, indices: [0, 1])
        }
        #expect(throws: P5MeshError.indexOutOfBounds(3)) {
            _ = try P5Mesh(vertices: vertices, indices: [0, 1, 3])
        }

        var invalidVertices = Array(repeating: vertices[0], count: 8)
        invalidVertices[0].position.x = .nan
        invalidVertices[1].normal.y = .infinity
        invalidVertices[2].textureCoordinate.u = .nan
        invalidVertices[3].textureCoordinate.v = .nan
        invalidVertices[4].color.x = .nan
        invalidVertices[5].color.y = .nan
        invalidVertices[6].color.z = .nan
        invalidVertices[7].color.w = .nan
        for invalid in invalidVertices {
            #expect(throws: P5MeshError.invalidVertex(1)) {
                _ = try P5Mesh(vertices: [vertices[0], invalid, vertices[2]], indices: [0, 1, 2])
            }
        }

        let degenerate = try P5Mesh(
            vertices: [
                P5Vertex3D(position: .zero),
                P5Vertex3D(position: P5Vector(x: 1)),
                P5Vertex3D(position: P5Vector(x: 2)),
            ],
            indices: [0, 1, 2]
        )
        #expect(throws: P5MeshError.degenerateTriangle(0)) {
            _ = try degenerate.calculatingNormals()
        }

        let unreferenced = try P5Mesh(
            vertices: vertices + [P5Vertex3D(position: P5Vector(z: 1))],
            indices: [0, 1, 2]
        )
        #expect(throws: P5MeshError.invalidVertex(3)) {
            _ = try unreferenced.calculatingNormals()
        }

        var corruptMesh = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(mesh)) as? [String: Any]
        )
        corruptMesh["indices"] = [0, 1, 9]
        #expect(throws: P5MeshError.indexOutOfBounds(9)) {
            _ = try JSONDecoder().decode(
                P5Mesh.self,
                from: JSONSerialization.data(withJSONObject: corruptMesh)
            )
        }

        var corruptBounds = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(mesh.bounds)) as? [String: Any]
        )
        corruptBounds["minimum"] = corruptBounds["maximum"]
        var maximum = try #require(corruptBounds["maximum"] as? [String: Any])
        maximum["x"] = -2
        corruptBounds["maximum"] = maximum
        #expect(throws: P5MeshError.invalidDimension) {
            _ = try JSONDecoder().decode(
                P5Bounds3D.self,
                from: JSONSerialization.data(withJSONObject: corruptBounds)
            )
        }

        for error in [
            P5MeshError.empty, .invalidVertex(1), .invalidIndexCount, .indexOutOfBounds(4),
            .degenerateTriangle(2), .invalidDimension, .insufficientSegments,
        ] {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Plane, box, and sphere primitives have stable topology")
    func primitives() throws {
        let plane = try P5Mesh.plane(width: 2, height: 4)
        #expect(plane.vertices.count == 4)
        #expect(plane.indices.count == 6)
        #expect(plane.bounds.size == P5Vector(x: 2, y: 4))

        let box = try P5Mesh.box(width: 2, height: 4, depth: 6)
        #expect(box.vertices.count == 24)
        #expect(box.indices.count == 36)
        #expect(box.bounds.size == P5Vector(x: 2, y: 4, z: 6))

        let sphere = try P5Mesh.sphere(radius: 2, segments: 3, rings: 2)
        #expect(sphere.vertices.count == 12)
        #expect(sphere.indices.count == 36)
        #expect(sphere.vertices.allSatisfy { abs($0.normal.mag() - 1) < 0.000_01 })

        for dimensions in [(Float.nan, Float(1)), (0, 1), (1, .nan), (1, 0)] {
            #expect(throws: P5MeshError.invalidDimension) {
                _ = try P5Mesh.plane(width: dimensions.0, height: dimensions.1)
            }
        }
        for dimensions in [
            (Float.nan, Float(1), Float(1)), (0, 1, 1), (1, .nan, 1), (1, 0, 1),
            (1, 1, .nan), (1, 1, 0),
        ] {
            #expect(throws: P5MeshError.invalidDimension) {
                _ = try P5Mesh.box(width: dimensions.0, height: dimensions.1, depth: dimensions.2)
            }
        }
        #expect(throws: P5MeshError.invalidDimension) { _ = try P5Mesh.sphere(radius: .nan) }
        #expect(throws: P5MeshError.invalidDimension) { _ = try P5Mesh.sphere(radius: 0) }
        #expect(throws: P5MeshError.insufficientSegments) {
            _ = try P5Mesh.sphere(segments: 2, rings: 2)
        }
        #expect(throws: P5MeshError.insufficientSegments) {
            _ = try P5Mesh.sphere(segments: 3, rings: 1)
        }
    }

    @Test("Invalid matrix and bounds construction terminates at public boundaries")
    func invalidConstruction() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Matrix4x4(
                    column0: SIMD4(.nan, 0, 0, 0),
                    column1: SIMD4(0, 1, 0, 0),
                    column2: SIMD4(0, 0, 1, 0),
                    column3: SIMD4(0, 0, 0, 1)
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Matrix4x4.translation(x: .nan, y: 0, z: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Matrix4x4.scale(x: 1, y: .nan, z: 1)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5Matrix4x4.rotationX(.nan) }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5Matrix4x4.rotationY(.nan) }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5Matrix4x4.rotationZ(.nan) }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5Matrix4x4.identity[-1, 0] }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5Matrix4x4.identity[0, 4] }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Bounds3D(minimum: P5Vector(x: 1), maximum: .zero)
            }
        #endif
    }

    @Test("OBJ parser triangulates, resolves indices, and reports malformed input")
    func objParsing() throws {
        let loader = P5OBJModelLoader()
        let complete = """
            # complete quad
            mtllib scene.mtl
            o Plane
            g front
            s 1
            usemtl white
            v -1 -1 0
            v 1 -1 0
            v 1 1 0
            v -1 1 0
            vt 0 1 0
            vt 1 1
            vt 1 0
            vt 0 0
            vn 0 0 2
            f 1/1/1 2/2/1 3/3/1 4/4/1 # fan

            """
        let mesh = try loader.parse(complete)
        #expect(mesh.vertices.count == 4)
        #expect(mesh.indices == [0, 1, 2, 0, 2, 3])
        #expect(mesh.vertices.allSatisfy { $0.normal == P5Vector(x: 0, y: 0, z: 1) })
        #expect(try loader.parse(Data(complete.utf8)) == mesh)

        let generated = try loader.parse(
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf -3 -2 -1\n"
        )
        #expect(generated.vertices.allSatisfy { $0.normal == P5Vector(x: 0, y: 0, z: 1) })

        let shared = try loader.parse(
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nvn 0 0 1\nf 1//1 2//1 3//1\nf 1//1 2//1 3//1"
        )
        #expect(shared.vertices.count == 3)
        #expect(shared.indices.count == 6)

        let noTexture = try loader.parse(
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nvn 0 0 1\nf 1//1 2//1 3//1\n"
        )
        #expect(noTexture.vertices.allSatisfy { $0.textureCoordinate == P5TextureCoordinate() })

        let malformed: [String] = [
            "v 0 0\n",
            "v 0 bad 0\n",
            "v 0 inf 0\n",
            "vt 0\n",
            "vt 0 1 2 3\n",
            "vn 0 0\n",
            "vn 0 0 0\n",
            "f 1 2\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf /1 2 3\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/2/3/4 2 3\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf x 2 3\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 0 2 3\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 4 2 3\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf -4 -2 -1\n",
            "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/1 2 3\n",
            "l 1 2\n",
        ]
        for source in malformed {
            #expect(throws: P5Model3DError.self) { _ = try loader.parse(source) }
        }
        #expect(throws: P5Model3DError.invalidMesh(.empty)) { _ = try loader.parse("") }
        #expect(throws: P5Model3DError.invalidMesh(.degenerateTriangle(0))) {
            _ = try loader.parse("v 0 0 0\nv 1 0 0\nv 2 0 0\nf 1 2 3")
        }
        #expect(throws: P5Model3DError.invalidTextEncoding) {
            _ = try loader.parse(Data([0xFF]))
        }

        let errors: [P5Model3DError] = [
            .loadingFailed("load"), .invalidHTTPStatus(500), .invalidTextEncoding,
            .malformed(line: 2, reason: "bad"), .unsupportedStatement(line: 3, keyword: "l"),
            .invalidMesh(.empty),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("OBJ loading handles native files, responses, failures, and cancellation")
    func objLoading() async throws {
        let source = Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3".utf8)
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5OBJ-\(UUID().uuidString).obj"
        )
        defer { try? FileManager.default.removeItem(at: localURL) }
        try source.write(to: localURL)
        #expect(try await P5OBJModelLoader().load(from: localURL).indices == [0, 1, 2])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [P5OBJURLProtocol.self]
        let nativeRemote = try #require(URL(string: "https://p5-obj.test/mesh.obj"))
        #expect(
            try await P5OBJModelLoader(session: URLSession(configuration: configuration))
                .load(from: nativeRemote).vertices.count == 3
        )

        let remoteURL = try #require(URL(string: "https://model.test/mesh.obj"))
        let response = try #require(
            HTTPURLResponse(
                url: remoteURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        var runtime = P5OBJLoadingRuntime(
            localData: { _ in source },
            remoteData: { _ in (source, response) }
        )
        #expect(
            try await P5OBJModelLoader(runtime: runtime).load(from: remoteURL).indices.count == 3)

        let nonHTTP = URLResponse(
            url: remoteURL,
            mimeType: nil,
            expectedContentLength: source.count,
            textEncodingName: nil
        )
        runtime.remoteData = { _ in (source, nonHTTP) }
        #expect(
            try await P5OBJModelLoader(runtime: runtime).load(from: remoteURL).vertices.count == 3)

        let failedResponse = try #require(
            HTTPURLResponse(
                url: remoteURL,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )
        )
        runtime.remoteData = { _ in (source, failedResponse) }
        await #expect(throws: P5Model3DError.invalidHTTPStatus(503)) {
            _ = try await P5OBJModelLoader(runtime: runtime).load(from: remoteURL)
        }

        runtime.localData = { _ in throw OBJStubError.failed }
        await #expect(throws: P5Model3DError.loadingFailed("failed")) {
            _ = try await P5OBJModelLoader(runtime: runtime).load(from: localURL)
        }
        runtime.localData = { _ in throw P5Model3DError.invalidTextEncoding }
        await #expect(throws: P5Model3DError.invalidTextEncoding) {
            _ = try await P5OBJModelLoader(runtime: runtime).load(from: localURL)
        }

        let beforeLoader = P5OBJModelLoader(runtime: runtime)
        let cancelledBefore = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await beforeLoader.load(from: localURL)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelledBefore.value }

        runtime.localData = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return source
        }
        let afterLoader = P5OBJModelLoader(runtime: runtime)
        let cancelledAfter = Task {
            try await afterLoader.load(from: localURL)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelledAfter.value }

        runtime.localData = { _ in throw CancellationError() }
        let cancellationLoader = P5OBJModelLoader(runtime: runtime)
        let cancellationFailure = Task {
            try await cancellationLoader.load(from: localURL)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancellationFailure.value }
    }
}

private enum OBJStubError: Error, LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

private final class P5OBJURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "p5-obj.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3".utf8)
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension P5Vector {
    fileprivate func isApproximately(_ other: Self, tolerance: CGFloat = 0.000_01) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(z - other.z) <= tolerance
    }
}

extension Float {
    fileprivate func isApproximately(_ other: Self, tolerance: Self = 0.000_01) -> Bool {
        abs(self - other) <= tolerance
    }
}
