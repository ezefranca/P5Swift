#if canImport(Metal)
    import CoreGraphics
    import Foundation
    import Metal
    import MetalKit
    import QuartzCore
    import Testing

    @testable import P5

    @Suite("P5 Metal 3D rendering", .serialized)
    struct P5MetalRendererTests {
        @Test("Render state, materials, and statistics validate and serialize")
        func valueTypes() throws {
            try expectRoundTrip(P5BlendMode3D.allCases)
            try expectRoundTrip(P5DepthMode3D.allCases)
            try expectRoundTrip(P5CullMode3D.allCases)
            try expectRoundTrip(P5Winding3D.allCases)
            try expectRoundTrip(P5StencilCompare3D.allCases)
            try expectRoundTrip(P5StencilOperation3D.allCases)
            try expectRoundTrip(P5PixelFormat3D.allCases)

            let stencil = P5StencilConfiguration3D(
                compare: .greaterEqual,
                stencilFailure: .zero,
                depthFailure: .decrementClamp,
                pass: .incrementClamp,
                referenceValue: 42,
                readMask: 0x0F,
                writeMask: 0xF0
            )
            #expect(stencil.compare == .greaterEqual)
            #expect(stencil.stencilFailure == .zero)
            #expect(stencil.depthFailure == .decrementClamp)
            #expect(stencil.pass == .incrementClamp)
            #expect(stencil.referenceValue == 42)
            #expect(stencil.readMask == 0x0F)
            #expect(stencil.writeMask == 0xF0)
            try expectRoundTrip(stencil)

            let standard = P5RenderConfiguration3D.standard
            #expect(standard.colorFormat == .bgra8Unorm)
            #expect(standard.sampleCount == 1)
            #expect(standard.clearColor == SIMD4(0, 0, 0, 1))
            #expect(standard.depthMode == .readWrite)
            #expect(standard.stencil == nil)
            #expect(standard.cullMode == .back)
            #expect(standard.frontFace == .counterClockwise)
            #expect(standard.blendMode == .opaque)

            let configured = try P5RenderConfiguration3D(
                colorFormat: .rgba16Float,
                sampleCount: 4,
                clearColor: SIMD4(0.1, 0.2, 0.3, 0.4),
                depthMode: .readOnly,
                stencil: stencil,
                cullMode: .front,
                frontFace: .clockwise,
                blendMode: .alpha
            )
            try expectRoundTrip(configured)
            for sampleCount in [0, 3, 16] {
                #expect(throws: P5Metal3DError.invalidConfiguration) {
                    _ = try P5RenderConfiguration3D(sampleCount: sampleCount)
                }
            }
            for clearColor in invalidRGBAValues() {
                #expect(throws: P5Metal3DError.invalidConfiguration) {
                    _ = try P5RenderConfiguration3D(clearColor: clearColor)
                }
            }

            var corrupt = try #require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(configured))
                    as? [String: Any]
            )
            corrupt["sampleCount"] = 3
            #expect(throws: P5Metal3DError.invalidConfiguration) {
                _ = try JSONDecoder().decode(
                    P5RenderConfiguration3D.self,
                    from: JSONSerialization.data(withJSONObject: corrupt)
                )
            }

            let textureConfiguration = P5TextureConfiguration3D(
                usesLinearFiltering: false,
                repeats: true,
                generatesMipmaps: false
            )
            #expect(textureConfiguration.usesLinearFiltering == false)
            #expect(textureConfiguration.repeats)
            #expect(textureConfiguration.generatesMipmaps == false)
            try expectRoundTrip(textureConfiguration)

            let material = try P5Material3D(
                baseColor: SIMD4(0.1, 0.2, 0.3, 0.4),
                emissiveColor: SIMD3(0.5, 0.6, 0.7),
                metallic: 0.8,
                roughness: 0.9,
                isUnlit: true
            )
            #expect(material.baseColor == SIMD4(0.1, 0.2, 0.3, 0.4))
            #expect(material.emissiveColor == SIMD3(0.5, 0.6, 0.7))
            #expect(material.metallic == 0.8)
            #expect(material.roughness == 0.9)
            #expect(material.isUnlit)
            #expect(material.texture == nil)
            #expect(material.shader == nil)
            for baseColor in invalidFiniteRGBAValues() {
                #expect(throws: P5Metal3DError.invalidMaterial) {
                    _ = try P5Material3D(baseColor: baseColor)
                }
            }
            for emissiveColor in invalidFiniteRGBValues() {
                #expect(throws: P5Metal3DError.invalidMaterial) {
                    _ = try P5Material3D(emissiveColor: emissiveColor)
                }
            }
            for metallic in [Float.nan, -.infinity, -0.01, 1.01, .infinity] {
                #expect(throws: P5Metal3DError.invalidMaterial) {
                    _ = try P5Material3D(metallic: metallic)
                }
            }
            for roughness in [Float.nan, -.infinity, -0.01, 1.01, .infinity] {
                #expect(throws: P5Metal3DError.invalidMaterial) {
                    _ = try P5Material3D(roughness: roughness)
                }
            }

            let statistics = P5MetalRendererStatistics(
                submittedFrames: 4,
                completedFrames: 3,
                lastDrawCallCount: 2,
                lastTriangleCount: 12,
                lastGPUTime: 0.25
            )
            #expect(statistics.submittedFrames == 4)
            #expect(statistics.completedFrames == 3)
            #expect(statistics.lastDrawCallCount == 2)
            #expect(statistics.lastTriangleCount == 12)
            #expect(statistics.lastGPUTime == 0.25)
            try expectRoundTrip(statistics)
            try expectRoundTrip(P5MetalRendererStatistics())
        }

        @Test("Metal mappings cover every supported render state")
        func metalMappings() throws {
            #expect(P5PixelFormat3D.bgra8Unorm.metal == .bgra8Unorm)
            #expect(P5PixelFormat3D.bgra8UnormSRGB.metal == .bgra8Unorm_srgb)
            #expect(P5PixelFormat3D.rgba16Float.metal == .rgba16Float)
            #expect(P5PixelFormat3D(metal: .bgra8Unorm) == .bgra8Unorm)
            #expect(P5PixelFormat3D(metal: .bgra8Unorm_srgb) == .bgra8UnormSRGB)
            #expect(P5PixelFormat3D(metal: .rgba16Float) == .rgba16Float)
            #expect(P5PixelFormat3D(metal: .r8Unorm) == nil)

            #expect(P5CullMode3D.none.metal == .none)
            #expect(P5CullMode3D.back.metal == .back)
            #expect(P5CullMode3D.front.metal == .front)
            #expect(P5Winding3D.counterClockwise.metal == .counterClockwise)
            #expect(P5Winding3D.clockwise.metal == .clockwise)

            let comparisons: [MTLCompareFunction] = [
                .always, .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual, .never,
            ]
            #expect(P5StencilCompare3D.allCases.map(\.metal) == comparisons)
            let operations: [MTLStencilOperation] = [
                .keep, .zero, .replace, .incrementClamp, .decrementClamp, .invert,
            ]
            #expect(P5StencilOperation3D.allCases.map(\.metal) == operations)

            P5BlendMode3D.opaque.apply(to: nil)
            let opaque = MTLRenderPipelineColorAttachmentDescriptor()
            P5BlendMode3D.opaque.apply(to: opaque)
            #expect(opaque.isBlendingEnabled == false)
            let alpha = MTLRenderPipelineColorAttachmentDescriptor()
            P5BlendMode3D.alpha.apply(to: alpha)
            #expect(alpha.isBlendingEnabled)
            #expect(alpha.sourceRGBBlendFactor == .sourceAlpha)
            #expect(alpha.destinationRGBBlendFactor == .oneMinusSourceAlpha)
            #expect(alpha.sourceAlphaBlendFactor == .one)
            #expect(alpha.destinationAlphaBlendFactor == .oneMinusSourceAlpha)
            let additive = MTLRenderPipelineColorAttachmentDescriptor()
            P5BlendMode3D.additive.apply(to: additive)
            #expect(additive.isBlendingEnabled)
            #expect(additive.destinationRGBBlendFactor == .one)
            #expect(additive.destinationAlphaBlendFactor == .one)

            let matrix = P5Matrix4x4.translation(x: 1, y: 2, z: 3).simdMatrix
            #expect(matrix.columns.3 == SIMD4(1, 2, 3, 1))
            #expect(P5Vector(x: 1, y: 2, z: 3).metalFloat3 == SIMD3(1, 2, 3))
            #expect(SIMD3<Float>(1, 2, 3).allFinite)
            #expect(SIMD3<Float>(.nan, 2, 3).allFinite == false)

            let vertex = P5GPUVertex3D(
                P5Vertex3D(
                    position: P5Vector(x: 1, y: 2, z: 3),
                    normal: P5Vector(x: 4, y: 5, z: 6),
                    textureCoordinate: P5TextureCoordinate(u: 7, v: 8),
                    color: SIMD4(9, 10, 11, 12)
                )
            )
            #expect(vertex.position == SIMD3(1, 2, 3))
            #expect(vertex.normal == SIMD3(4, 5, 6))
            #expect(vertex.textureCoordinate == SIMD2(7, 8))
            #expect(vertex.color == SIMD4(9, 10, 11, 12))
            #expect(MemoryLayout<P5GPUVertex3D>.stride == 64)
            #expect(MemoryLayout<P5GPUUniforms3D>.stride == 240)
            #expect(MemoryLayout<P5GPULight3D>.stride == 48)
        }

        @Test("Every renderer error has a stable diagnostic")
        func diagnostics() {
            let errors: [P5Metal3DError] = [
                .unavailable,
                .shaderSourceUnavailable,
                .shaderCompilationFailed("compile"),
                .shaderFunctionUnavailable("vertex"),
                .pipelineCreationFailed("pipeline"),
                .commandQueueCreationFailed,
                .samplerCreationFailed,
                .vertexBufferCreationFailed,
                .indexBufferCreationFailed,
                .textureCreationFailed,
                .renderTargetCreationFailed,
                .depthStencilCreationFailed,
                .multisampleCreationFailed,
                .unsupportedSampleCount(8),
                .invalidRenderTarget,
                .renderTargetFormatMismatch,
                .invalidConfiguration,
                .invalidMaterial,
                .invalidLight(2),
                .nonInvertibleModelMatrix(3),
                .commandBufferCreationFailed,
                .commandEncoderCreationFailed,
                .commandExecutionFailed(status: 4, message: "lost"),
                .targetReadbackUnavailable,
                .invalidFramePacing,
            ]
            for error in errors {
                #expect(error.errorDescription?.isEmpty == false)
            }
            #expect(Set(errors).count == errors.count)
        }

        @Test("Command completion status and GPU timing are deterministic")
        func completionStatus() throws {
            #expect(
                try P5MetalExecutionHooks.completedGPUTime(
                    status: .completed,
                    message: nil,
                    startTime: 2,
                    endTime: 2.25
                ) == 0.25
            )
            #expect(
                try P5MetalExecutionHooks.completedGPUTime(
                    status: .completed,
                    message: nil,
                    startTime: 2,
                    endTime: 2
                ) == nil
            )
            #expect(
                throws: P5Metal3DError.commandExecutionFailed(
                    status: Int(MTLCommandBufferStatus.error.rawValue),
                    message: "injected"
                )
            ) {
                _ = try P5MetalExecutionHooks.completedGPUTime(
                    status: .error,
                    message: "injected",
                    startTime: 0,
                    endTime: 0
                )
            }
            #expect(
                throws: P5Metal3DError.commandExecutionFailed(
                    status: Int(MTLCommandBufferStatus.notEnqueued.rawValue),
                    message: "The command buffer did not complete."
                )
            ) {
                _ = try P5MetalExecutionHooks.completedGPUTime(
                    status: .notEnqueued,
                    message: nil,
                    startTime: 0,
                    endTime: 0
                )
            }
        }

        @Test("Renderer initialization reports every native construction failure")
        func rendererInitializationFailures() async throws {
            let device = try metalDevice()
            _ = P5MetalResourceFactory.system.makeDefaultLibrary(device)

            var factory = makeFactory(device: device)
            factory.makeDevice = { nil }
            #expect(throws: P5Metal3DError.unavailable) {
                _ = try P5MetalRenderer(
                    resourceFactory: factory,
                    executionHooks: .system
                )
            }

            factory = makeFactory(device: device)
            factory.loadShaderSource = { nil }
            factory.makeDefaultLibrary = { _ in nil }
            #expect(throws: P5Metal3DError.shaderSourceUnavailable) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            factory = makeFactory(device: device)
            factory.loadShaderSource = { nil }
            factory.makeDefaultLibrary = { device in
                try? device.makeLibrary(source: p5TestShaderSource, options: nil)
            }
            let compiled = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            #expect(compiled.deviceName == device.name)

            factory = makeFactory(device: device)
            factory.makeLibrary = { _, _ in throw P5MetalTestError.injected }
            #expect(throws: P5Metal3DError.shaderCompilationFailed("injected")) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            factory = makeFactory(device: device)
            factory.makeFunction = { library, name in
                name == "p5Vertex3D" ? nil : library.makeFunction(name: name)
            }
            #expect(throws: P5Metal3DError.shaderFunctionUnavailable("p5Vertex3D")) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            factory = makeFactory(device: device)
            factory.makeFunction = { library, name in
                name == "p5Fragment3D" ? nil : library.makeFunction(name: name)
            }
            #expect(throws: P5Metal3DError.shaderFunctionUnavailable("p5Fragment3D")) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            factory = makeFactory(device: device)
            factory.makeCommandQueue = { _ in nil }
            #expect(throws: P5Metal3DError.commandQueueCreationFailed) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            factory = makeFactory(device: device)
            factory.makeSampler = { _, _ in nil }
            #expect(throws: P5Metal3DError.samplerCreationFailed) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            factory = makeFactory(device: device)
            factory.makeTexture = { _, _ in nil }
            #expect(throws: P5Metal3DError.textureCreationFailed) {
                _ = try P5MetalRenderer(resourceFactory: factory, executionHooks: .system)
            }

            let explicit = try P5MetalRenderer(device: device)
            #expect(explicit.deviceName == device.name)
            let initialStatistics = await explicit.statistics()
            #expect(initialStatistics == P5MetalRendererStatistics())
            let automatic = try P5MetalRenderer()
            #expect(automatic.deviceName.isEmpty == false)
            #expect(P5MetalRenderer.isAvailable)
        }

        @Test("Shaders, meshes, and textures own validated GPU resources")
        func resources() async throws {
            let device = try metalDevice()
            let source = p5TestShaderSource
            #expect(P5MetalResourceFactory.shaderSource(at: nil) == nil)
            #expect(
                P5MetalResourceFactory.shaderSource(
                    at: URL(fileURLWithPath: "/definitely/missing/p5-shader.metal")
                ) == nil
            )
            let renderer = try P5MetalRenderer(device: device)

            await #expect(throws: P5Metal3DError.shaderSourceUnavailable) {
                _ = try await renderer.makeShader(
                    source: " \n\t ",
                    vertexFunction: "p5Vertex3D",
                    fragmentFunction: "p5Fragment3D"
                )
            }
            let shader = try await renderer.makeShader(
                source: source,
                vertexFunction: "p5Vertex3D",
                fragmentFunction: "p5Fragment3D"
            )
            #expect(shader.vertexFunctionName == "p5Vertex3D")
            #expect(shader.fragmentFunctionName == "p5Fragment3D")

            var failingFactory = makeFactory(device: device)
            let compileState = P5MetalFactoryState()
            let systemLibrary = failingFactory.makeLibrary
            failingFactory.makeLibrary = { device, source in
                compileState.libraryCalls += 1
                guard compileState.libraryCalls == 1 else { throw P5MetalTestError.injected }
                return try systemLibrary(device, source)
            }
            let compilationRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.shaderCompilationFailed("injected")) {
                _ = try await compilationRenderer.makeShader(
                    source: source,
                    vertexFunction: "p5Vertex3D",
                    fragmentFunction: "p5Fragment3D"
                )
            }

            failingFactory = makeFactory(device: device)
            failingFactory.makeFunction = { library, name in
                name == "missingVertex" ? nil : library.makeFunction(name: name)
            }
            let missingVertexRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.shaderFunctionUnavailable("missingVertex")) {
                _ = try await missingVertexRenderer.makeShader(
                    source: source,
                    vertexFunction: "missingVertex",
                    fragmentFunction: "p5Fragment3D"
                )
            }

            failingFactory = makeFactory(device: device)
            failingFactory.makeFunction = { library, name in
                name == "missingFragment" ? nil : library.makeFunction(name: name)
            }
            let missingFragmentRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.shaderFunctionUnavailable("missingFragment")) {
                _ = try await missingFragmentRenderer.makeShader(
                    source: source,
                    vertexFunction: "p5Vertex3D",
                    fragmentFunction: "missingFragment"
                )
            }

            let plane = try P5Mesh.plane(width: 2, height: 4)
            let metalMesh = try await renderer.makeMesh(plane)
            #expect(metalMesh.vertexCount == plane.vertices.count)
            #expect(metalMesh.indexCount == plane.indices.count)
            #expect(metalMesh.bounds == plane.bounds)
            #expect(metalMesh.vertexBuffer.length == plane.vertices.count * 64)
            #expect(metalMesh.indexBuffer.length == plane.indices.count * 4)

            failingFactory = makeFactory(device: device)
            failingFactory.makeBuffer = { _, _, _ in nil }
            let vertexFailureRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.vertexBufferCreationFailed) {
                _ = try await vertexFailureRenderer.makeMesh(plane)
            }

            failingFactory = makeFactory(device: device)
            let bufferState = P5MetalFactoryState()
            let systemBuffer = failingFactory.makeBuffer
            failingFactory.makeBuffer = { device, bytes, count in
                bufferState.bufferCalls += 1
                return bufferState.bufferCalls == 1 ? systemBuffer(device, bytes, count) : nil
            }
            let indexFailureRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.indexBufferCreationFailed) {
                _ = try await indexFailureRenderer.makeMesh(plane)
            }

            let image = try testImage()
            let nearestTexture = try await renderer.makeTexture(
                from: image,
                configuration: P5TextureConfiguration3D(
                    usesLinearFiltering: false,
                    repeats: true,
                    generatesMipmaps: false
                )
            )
            #expect(nearestTexture.width == 2)
            #expect(nearestTexture.height == 2)
            #expect(nearestTexture.hasMipmaps == false)

            let linearTexture = try await renderer.makeTexture(from: image)
            #expect(linearTexture.hasMipmaps)

            failingFactory = makeFactory(device: device)
            failingFactory.makeImageTexture = { _, _, _ in throw P5MetalTestError.injected }
            let textureFailureRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.textureCreationFailed) {
                _ = try await textureFailureRenderer.makeTexture(from: image)
            }

            failingFactory = makeFactory(device: device)
            let samplerState = P5MetalFactoryState()
            let systemSampler = failingFactory.makeSampler
            failingFactory.makeSampler = { device, descriptor in
                samplerState.samplerCalls += 1
                return samplerState.samplerCalls == 1
                    ? systemSampler(device, descriptor) : nil
            }
            let samplerFailureRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.samplerCreationFailed) {
                _ = try await samplerFailureRenderer.makeTexture(from: image)
            }
        }

        @Test("Lights validate and retain their shader ABI representation")
        func lights() throws {
            let sourceLights: [P5Light3D] = [
                .ambient(color: SIMD3(0.1, 0.2, 0.3), intensity: 0.4),
                .directional(
                    direction: P5Vector(x: 0, y: -2, z: 0),
                    color: SIMD3(0.5, 0.6, 0.7),
                    intensity: 0.8
                ),
                .point(
                    position: P5Vector(x: 1, y: 2, z: 3),
                    color: SIMD3(0.9, 0.8, 0.7),
                    intensity: 0.6,
                    range: 12
                ),
            ]
            for light in sourceLights { try expectRoundTrip(light) }
            let lights = try P5MetalRenderer.gpuLights(sourceLights)
            #expect(lights.count == 3)
            #expect(lights[0].positionAndKind.w == 0)
            #expect(lights[0].colorAndIntensity == SIMD4(0.1, 0.2, 0.3, 0.4))
            #expect(lights[1].positionAndKind.w == 1)
            #expect(lights[1].directionAndRange == SIMD4(0, -1, 0, 0))
            #expect(lights[2].positionAndKind == SIMD4(1, 2, 3, 2))
            #expect(lights[2].directionAndRange.w == 12)
            #expect(try P5MetalRenderer.gpuLights([]).isEmpty)

            #expect(throws: P5Metal3DError.invalidLight(P5MetalRenderer.maximumLightCount)) {
                _ = try P5MetalRenderer.gpuLights(
                    Array(repeating: sourceLights[0], count: P5MetalRenderer.maximumLightCount + 1)
                )
            }
            for color in invalidLightColors() {
                #expect(throws: P5Metal3DError.invalidLight(0)) {
                    _ = try P5MetalRenderer.gpuLights([.ambient(color: color, intensity: 1)])
                }
            }
            for intensity in [Float.nan, -Float.infinity, -1] {
                #expect(throws: P5Metal3DError.invalidLight(0)) {
                    _ = try P5MetalRenderer.gpuLights([
                        .ambient(color: SIMD3(repeating: 1), intensity: intensity)
                    ])
                }
            }
            let invalidDirections = [
                P5Vector.zero,
                P5Vector(x: .nan, y: 1, z: 1),
                P5Vector(x: 1, y: .nan, z: 1),
                P5Vector(x: 1, y: 1, z: .nan),
            ]
            for direction in invalidDirections {
                #expect(throws: P5Metal3DError.invalidLight(0)) {
                    _ = try P5MetalRenderer.gpuLights([
                        .directional(
                            direction: direction,
                            color: SIMD3(repeating: 1),
                            intensity: 1
                        )
                    ])
                }
            }
            #expect(throws: P5Metal3DError.invalidLight(0)) {
                _ = try P5MetalRenderer.gpuLights([
                    .directional(
                        direction: P5Vector(x: 1),
                        color: SIMD3(-1, 1, 1),
                        intensity: 1
                    )
                ])
            }
            #expect(throws: P5Metal3DError.invalidLight(0)) {
                _ = try P5MetalRenderer.gpuLights([
                    .directional(
                        direction: P5Vector(x: 1),
                        color: SIMD3(repeating: 1),
                        intensity: -1
                    )
                ])
            }
            let invalidPositions = [
                P5Vector(x: .nan), P5Vector(y: .nan), P5Vector(z: .nan),
            ]
            for position in invalidPositions {
                #expect(throws: P5Metal3DError.invalidLight(0)) {
                    _ = try P5MetalRenderer.gpuLights([
                        .point(
                            position: position,
                            color: SIMD3(repeating: 1),
                            intensity: 1,
                            range: 1
                        )
                    ])
                }
            }
            #expect(throws: P5Metal3DError.invalidLight(0)) {
                _ = try P5MetalRenderer.gpuLights([
                    .point(
                        position: .zero,
                        color: SIMD3(-1, 1, 1),
                        intensity: 1,
                        range: 1
                    )
                ])
            }
            #expect(throws: P5Metal3DError.invalidLight(0)) {
                _ = try P5MetalRenderer.gpuLights([
                    .point(
                        position: .zero,
                        color: SIMD3(repeating: 1),
                        intensity: -1,
                        range: 1
                    )
                ])
            }
            for range in [Float.nan, -Float.infinity, 0, -1] {
                #expect(throws: P5Metal3DError.invalidLight(0)) {
                    _ = try P5MetalRenderer.gpuLights([
                        .point(
                            position: .zero,
                            color: SIMD3(repeating: 1),
                            intensity: 1,
                            range: range
                        )
                    ])
                }
            }
        }

        @Test("Render targets validate ownership, formats, and readback")
        func renderTargets() async throws {
            let device = try metalDevice()
            let renderer = try P5MetalRenderer(device: device)
            for format in P5PixelFormat3D.allCases {
                let target = try await renderer.makeRenderTarget(
                    width: 3,
                    height: 2,
                    colorFormat: format
                )
                #expect(target.width == 3)
                #expect(target.height == 2)
                #expect(target.colorFormat == format)
                #expect(target.texture.usage.contains(.renderTarget))
            }
            await #expect(throws: P5Metal3DError.invalidRenderTarget) {
                _ = try await renderer.makeRenderTarget(width: 0, height: 1)
            }
            await #expect(throws: P5Metal3DError.invalidRenderTarget) {
                _ = try await renderer.makeRenderTarget(width: 1, height: 0)
            }

            var failingFactory = makeFactory(device: device)
            let state = P5MetalFactoryState()
            let systemTexture = failingFactory.makeTexture
            failingFactory.makeTexture = { device, descriptor in
                state.textureCalls += 1
                return state.textureCalls == 1 ? systemTexture(device, descriptor) : nil
            }
            let failingRenderer = try P5MetalRenderer(
                resourceFactory: failingFactory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.renderTargetCreationFailed) {
                _ = try await failingRenderer.makeRenderTarget(width: 1, height: 1)
            }

            let validTexture = try makeTexture(
                device: device,
                type: .type2D,
                format: .bgra8Unorm,
                usage: [.renderTarget, .shaderRead],
                storage: .shared
            )
            let wrapped = try P5MetalRenderTarget(texture: validTexture)
            #expect(wrapped.width == 2)
            #expect(wrapped.height == 2)
            let wrappedWithDrawable = try P5MetalRenderTarget(
                texture: validTexture,
                drawable: nil
            )
            #expect(wrappedWithDrawable.drawable == nil)

            let bytes: [UInt8] = [
                1, 2, 3, 4, 5, 6, 7, 8,
                9, 10, 11, 12, 13, 14, 15, 16,
            ]
            let byteStorage = NSData(bytes: bytes, length: bytes.count)
            validTexture.replace(
                region: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0,
                withBytes: byteStorage.bytes,
                bytesPerRow: 8
            )
            let pixelBuffer = try wrapped.pixelBuffer(pixelDensity: 2)
            #expect(pixelBuffer.width == 2)
            #expect(pixelBuffer.height == 2)
            #expect(pixelBuffer.pixelDensity == 2)
            #expect(
                pixelBuffer.bytes == [
                    3, 2, 1, 4, 7, 6, 5, 8,
                    11, 10, 9, 12, 15, 14, 13, 16,
                ]
            )

            let privateTexture = try makeTexture(
                device: device,
                type: .type2D,
                format: .bgra8Unorm,
                usage: .renderTarget,
                storage: .private
            )
            let privateTarget = try P5MetalRenderTarget(texture: privateTexture)
            #expect(throws: P5Metal3DError.targetReadbackUnavailable) {
                _ = try privateTarget.pixelBuffer()
            }
            let floatTexture = try makeTexture(
                device: device,
                type: .type2D,
                format: .rgba16Float,
                usage: .renderTarget,
                storage: .shared
            )
            let floatTarget = try P5MetalRenderTarget(texture: floatTexture)
            #expect(throws: P5Metal3DError.targetReadbackUnavailable) {
                _ = try floatTarget.pixelBuffer()
            }

            let invalidUsage = try makeTexture(
                device: device,
                type: .type2D,
                format: .bgra8Unorm,
                usage: .shaderRead,
                storage: .shared
            )
            #expect(throws: P5Metal3DError.invalidRenderTarget) {
                _ = try P5MetalRenderTarget(texture: invalidUsage)
            }
            #expect(throws: P5Metal3DError.invalidRenderTarget) {
                _ = try P5MetalRenderTarget(texture: invalidUsage, drawable: nil)
            }
            let invalidFormat = try makeTexture(
                device: device,
                type: .type2D,
                format: .r8Unorm,
                usage: .renderTarget,
                storage: .shared
            )
            #expect(throws: P5Metal3DError.invalidRenderTarget) {
                _ = try P5MetalRenderTarget(texture: invalidFormat)
            }
            let cube = try makeTexture(
                device: device,
                type: .typeCube,
                format: .bgra8Unorm,
                usage: .renderTarget,
                storage: .private
            )
            #expect(throws: P5Metal3DError.invalidRenderTarget) {
                _ = try P5MetalRenderTarget(texture: cube)
            }
            if device.supportsTextureSampleCount(4) {
                let multisample = try makeTexture(
                    device: device,
                    type: .type2DMultisample,
                    format: .bgra8Unorm,
                    usage: .renderTarget,
                    storage: .private,
                    sampleCount: 4
                )
                #expect(throws: P5Metal3DError.invalidRenderTarget) {
                    _ = try P5MetalRenderTarget(texture: multisample)
                }
            }
        }

        @MainActor
        @Test("MetalKit view pacing is validated and applied")
        func viewConfiguration() async throws {
            let device = try metalDevice()
            let configuration = try P5MetalViewConfiguration(
                preferredFramesPerSecond: 120,
                drawsOnDemand: true,
                colorFormat: .bgra8UnormSRGB
            )
            #expect(configuration.preferredFramesPerSecond == 120)
            #expect(configuration.drawsOnDemand)
            #expect(configuration.colorFormat == .bgra8UnormSRGB)
            try expectRoundTrip(configuration)
            for frameRate in [0, 241] {
                #expect(throws: P5Metal3DError.invalidFramePacing) {
                    _ = try P5MetalViewConfiguration(preferredFramesPerSecond: frameRate)
                }
            }

            let view = MTKView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
            configuration.apply(to: view, device: device)
            #expect(view.device?.name == device.name)
            #expect(view.colorPixelFormat == .bgra8Unorm_srgb)
            #expect(view.depthStencilPixelFormat == .invalid)
            #expect(view.sampleCount == 1)
            #expect(view.preferredFramesPerSecond == 120)
            #expect(view.isPaused)
            #expect(view.enableSetNeedsDisplay)
            #expect(view.framebufferOnly == false)
            let optionalCurrent = try configuration.renderTarget(from: view)
            let current = try #require(optionalCurrent)
            #expect(current.width > 0)
            #expect(current.height > 0)
            let renderer = try P5MetalRenderer(device: device)
            let scene = P5Scene3D(camera: try P5Camera3D(), lights: [], instances: [])
            let renderConfiguration = try P5RenderConfiguration3D(
                colorFormat: .bgra8UnormSRGB,
                depthMode: .disabled
            )
            _ = try await renderer.render(scene, to: current, configuration: renderConfiguration)

            let emptyView = MTKView(frame: .zero)
            #expect(try configuration.renderTarget(from: emptyView) == nil)
        }

        @Test("Scenes render through cached pipelines, depth state, MSAA, and textures")
        func rendering() async throws {
            let device = try metalDevice()
            let renderer = try P5MetalRenderer(device: device)
            let mesh = try await renderer.makeMesh(P5Mesh.plane(width: 2, height: 2))
            let texture = try await renderer.makeTexture(
                from: testImage(),
                configuration: P5TextureConfiguration3D(generatesMipmaps: false)
            )
            let source = p5TestShaderSource
            let shader = try await renderer.makeShader(
                source: source,
                vertexFunction: "p5Vertex3D",
                fragmentFunction: "p5Fragment3D"
            )
            let litMaterial = try P5Material3D(
                baseColor: SIMD4(0.8, 0.7, 0.6, 1),
                emissiveColor: SIMD3(0.01, 0.02, 0.03),
                metallic: 0.2,
                roughness: 0.4
            )
            let texturedMaterial = try P5Material3D(
                isUnlit: true,
                texture: texture,
                shader: shader
            )
            let first = P5MeshInstance3D(mesh: mesh, material: litMaterial)
            let second = P5MeshInstance3D(
                mesh: mesh,
                material: texturedMaterial,
                modelMatrix: .translation(x: 0.25, y: 0.25, z: 0)
            )
            #expect(first.mesh === mesh)
            #expect(first.material.baseColor == litMaterial.baseColor)
            #expect(first.modelMatrix == .identity)
            #expect(second.material.texture === texture)
            #expect(second.material.shader === shader)

            let camera = try P5Camera3D()
            let lights: [P5Light3D] = [
                .ambient(color: SIMD3(repeating: 0.2), intensity: 1),
                .directional(
                    direction: P5Vector(x: 0, y: 0, z: -1),
                    color: SIMD3(repeating: 1),
                    intensity: 0.8
                ),
                .point(
                    position: P5Vector(x: 0, y: 0, z: 2),
                    color: SIMD3(1, 0.5, 0.25),
                    intensity: 0.5,
                    range: 10
                ),
            ]
            let scene = P5Scene3D(camera: camera, lights: lights, instances: [first, second])
            #expect(scene.camera == camera)
            #expect(scene.lights == lights)
            #expect(scene.instances.count == 2)

            let target = try await renderer.makeRenderTarget(width: 32, height: 16)
            let firstStatistics = try await renderer.render(scene, to: target)
            #expect(firstStatistics.submittedFrames == 1)
            #expect(firstStatistics.completedFrames == 1)
            #expect(firstStatistics.lastDrawCallCount == 2)
            #expect(firstStatistics.lastTriangleCount == 4)
            if let gpuTime = firstStatistics.lastGPUTime { #expect(gpuTime >= 0) }
            let renderedPixels = try target.pixelBuffer()
            #expect(renderedPixels.bytes.count == 32 * 16 * 4)
            #expect(
                stride(from: 3, to: renderedPixels.bytes.count, by: 4).allSatisfy {
                    renderedPixels.bytes[$0] == 255
                })

            let secondStatistics = try await renderer.render(scene, to: target)
            #expect(secondStatistics.submittedFrames == 2)
            #expect(secondStatistics.completedFrames == 2)
            #expect(secondStatistics.lastDrawCallCount == 2)

            let emptyScene = P5Scene3D(camera: camera, lights: [], instances: [])
            let colorOnly = try P5RenderConfiguration3D(
                clearColor: SIMD4(0.25, 0.5, 0.75, 1),
                depthMode: .disabled,
                cullMode: .none,
                frontFace: .clockwise,
                blendMode: .alpha
            )
            let emptyStatistics = try await renderer.render(
                emptyScene,
                to: target,
                configuration: colorOnly
            )
            #expect(emptyStatistics.submittedFrames == 3)
            #expect(emptyStatistics.completedFrames == 3)
            #expect(emptyStatistics.lastDrawCallCount == 0)
            #expect(emptyStatistics.lastTriangleCount == 0)
            let cleared = try target.pixelBuffer()
            #expect(cleared.bytes[0] == 64)
            #expect(cleared.bytes[1] == 128)
            #expect(cleared.bytes[2] == 191)
            #expect(cleared.bytes[3] == 255)

            let stencil = P5StencilConfiguration3D(
                compare: .equal,
                stencilFailure: .invert,
                depthFailure: .zero,
                pass: .replace,
                referenceValue: 1
            )
            let stencilConfiguration = try P5RenderConfiguration3D(
                depthMode: .disabled,
                stencil: stencil,
                cullMode: .front,
                blendMode: .additive
            )
            let stencilStatistics = try await renderer.render(
                P5Scene3D(camera: camera, instances: [first]),
                to: target,
                configuration: stencilConfiguration
            )
            #expect(stencilStatistics.submittedFrames == 4)
            #expect(stencilStatistics.lastDrawCallCount == 1)

            let floatTarget = try await renderer.makeRenderTarget(
                width: 8,
                height: 8,
                colorFormat: .rgba16Float
            )
            let floatConfiguration = try P5RenderConfiguration3D(
                colorFormat: .rgba16Float,
                depthMode: .readOnly,
                cullMode: .front,
                blendMode: .additive
            )
            let floatStatistics = try await renderer.render(
                P5Scene3D(camera: camera, instances: [first]),
                to: floatTarget,
                configuration: floatConfiguration
            )
            #expect(floatStatistics.submittedFrames == 5)

            if device.supportsTextureSampleCount(4) {
                let multisampleConfiguration = try P5RenderConfiguration3D(
                    sampleCount: 4,
                    stencil: stencil,
                    cullMode: .none,
                    blendMode: .opaque
                )
                let multisampleStatistics = try await renderer.render(
                    P5Scene3D(camera: camera, instances: [first]),
                    to: target,
                    configuration: multisampleConfiguration
                )
                #expect(multisampleStatistics.submittedFrames == 6)
                #expect(multisampleStatistics.completedFrames == 6)
            }
            let finalStatistics = await renderer.statistics()
            #expect(finalStatistics.completedFrames >= 5)
        }

        @Test("Render submission surfaces allocation, encoding, execution, and scene failures")
        func renderingFailures() async throws {
            let device = try metalDevice()
            let resourceRenderer = try P5MetalRenderer(device: device)
            let mesh = try await resourceRenderer.makeMesh(P5Mesh.plane())
            let material = try P5Material3D()
            let camera = try P5Camera3D()
            let scene = P5Scene3D(
                camera: camera,
                instances: [P5MeshInstance3D(mesh: mesh, material: material)]
            )
            let emptyScene = P5Scene3D(camera: camera, lights: [], instances: [])
            let target = try await resourceRenderer.makeRenderTarget(width: 8, height: 8)

            let mismatch = try P5RenderConfiguration3D(colorFormat: .rgba16Float)
            await #expect(throws: P5Metal3DError.renderTargetFormatMismatch) {
                _ = try await resourceRenderer.render(scene, to: target, configuration: mismatch)
            }

            var factory = makeFactory(device: device)
            factory.supportsSampleCount = { _, _ in false }
            let unsupportedRenderer = try P5MetalRenderer(
                resourceFactory: factory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.unsupportedSampleCount(1)) {
                _ = try await unsupportedRenderer.render(emptyScene, to: target)
            }

            let singular = P5MeshInstance3D(
                mesh: mesh,
                material: material,
                modelMatrix: .scale(x: 0, y: 1, z: 1)
            )
            await #expect(throws: P5Metal3DError.nonInvertibleModelMatrix(0)) {
                _ = try await resourceRenderer.render(
                    P5Scene3D(camera: camera, instances: [singular]),
                    to: target
                )
            }
            let overflow = Float.greatestFiniteMagnitude
            let nonFinite = P5MeshInstance3D(
                mesh: mesh,
                material: material,
                modelMatrix: P5Matrix4x4(
                    column0: SIMD4(overflow, 0, 0, 0),
                    column1: SIMD4(0, overflow, 0, 0),
                    column2: SIMD4(0, 0, overflow, 0),
                    column3: SIMD4(0, 0, 0, 1)
                )
            )
            await #expect(throws: P5Metal3DError.nonInvertibleModelMatrix(0)) {
                _ = try await resourceRenderer.render(
                    P5Scene3D(camera: camera, instances: [nonFinite]),
                    to: target
                )
            }
            await #expect(throws: P5Metal3DError.invalidLight(0)) {
                _ = try await resourceRenderer.render(
                    P5Scene3D(
                        camera: camera,
                        lights: [.ambient(color: SIMD3(repeating: 1), intensity: -1)]
                    ),
                    to: target
                )
            }

            factory = makeFactory(device: device)
            let depthTextureState = P5MetalFactoryState()
            let systemTexture = factory.makeTexture
            factory.makeTexture = { device, descriptor in
                depthTextureState.textureCalls += 1
                return depthTextureState.textureCalls == 1
                    ? systemTexture(device, descriptor) : nil
            }
            let depthTextureRenderer = try P5MetalRenderer(
                resourceFactory: factory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.depthStencilCreationFailed) {
                _ = try await depthTextureRenderer.render(emptyScene, to: target)
            }

            if device.supportsTextureSampleCount(4) {
                factory = makeFactory(device: device)
                let multisampleTextureState = P5MetalFactoryState()
                let makeSystemTexture = factory.makeTexture
                factory.makeTexture = { device, descriptor in
                    multisampleTextureState.textureCalls += 1
                    return multisampleTextureState.textureCalls == 1
                        ? makeSystemTexture(device, descriptor) : nil
                }
                let multisampleRenderer = try P5MetalRenderer(
                    resourceFactory: factory,
                    executionHooks: .system
                )
                let multisample = try P5RenderConfiguration3D(
                    sampleCount: 4,
                    depthMode: .disabled
                )
                await #expect(throws: P5Metal3DError.multisampleCreationFailed) {
                    _ = try await multisampleRenderer.render(
                        emptyScene,
                        to: target,
                        configuration: multisample
                    )
                }
            }

            factory = makeFactory(device: device)
            factory.makePipeline = { _, _ in throw P5MetalTestError.injected }
            let pipelineRenderer = try P5MetalRenderer(
                resourceFactory: factory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.pipelineCreationFailed("injected")) {
                _ = try await pipelineRenderer.render(scene, to: target)
            }

            factory = makeFactory(device: device)
            factory.makeDepthState = { _, _ in nil }
            let depthStateRenderer = try P5MetalRenderer(
                resourceFactory: factory,
                executionHooks: .system
            )
            await #expect(throws: P5Metal3DError.depthStencilCreationFailed) {
                _ = try await depthStateRenderer.render(emptyScene, to: target)
            }

            var hooks = P5MetalExecutionHooks.system
            hooks.makeCommandBuffer = { _ in nil }
            let commandBufferRenderer = try P5MetalRenderer(
                resourceFactory: makeFactory(device: device),
                executionHooks: hooks
            )
            await #expect(throws: P5Metal3DError.commandBufferCreationFailed) {
                _ = try await commandBufferRenderer.render(emptyScene, to: target)
            }

            hooks = .system
            hooks.makeEncoder = { _, _ in nil }
            let encoderRenderer = try P5MetalRenderer(
                resourceFactory: makeFactory(device: device),
                executionHooks: hooks
            )
            await #expect(throws: P5Metal3DError.commandEncoderCreationFailed) {
                _ = try await encoderRenderer.render(emptyScene, to: target)
            }

            hooks = .system
            hooks.waitForCompletion = { _ in throw P5MetalTestError.injected }
            let executionRenderer = try P5MetalRenderer(
                resourceFactory: makeFactory(device: device),
                executionHooks: hooks
            )
            await #expect(throws: P5MetalTestError.injected) {
                _ = try await executionRenderer.render(emptyScene, to: target)
            }
            let failedStatistics = await executionRenderer.statistics()
            #expect(failedStatistics.submittedFrames == 1)
            #expect(failedStatistics.completedFrames == 0)

            let cancelledBefore = Task {
                await Task.yield()
                return try await resourceRenderer.render(emptyScene, to: target)
            }
            cancelledBefore.cancel()
            await #expect(throws: CancellationError.self) { _ = try await cancelledBefore.value }

            hooks = .system
            let systemEncoder = hooks.makeEncoder
            hooks.makeEncoder = { commandBuffer, descriptor in
                let encoder = systemEncoder(commandBuffer, descriptor)
                withUnsafeCurrentTask { $0?.cancel() }
                return encoder
            }
            let encodingCancellationRenderer = try P5MetalRenderer(
                resourceFactory: makeFactory(device: device),
                executionHooks: hooks
            )
            let cancelledDuringEncoding = Task {
                try await encodingCancellationRenderer.render(emptyScene, to: target)
            }
            await #expect(throws: CancellationError.self) {
                _ = try await cancelledDuringEncoding.value
            }

            hooks = .system
            let systemWait = hooks.waitForCompletion
            hooks.waitForCompletion = { commandBuffer in
                let gpuTime = try await systemWait(commandBuffer)
                withUnsafeCurrentTask { $0?.cancel() }
                return gpuTime
            }
            let completionCancellationRenderer = try P5MetalRenderer(
                resourceFactory: makeFactory(device: device),
                executionHooks: hooks
            )
            let cancelledAfterCompletion = Task {
                try await completionCancellationRenderer.render(emptyScene, to: target)
            }
            await #expect(throws: CancellationError.self) {
                _ = try await cancelledAfterCompletion.value
            }
        }

        @Test("Renderer wrappers release while long-running submissions remain bounded")
        func resourceLifetime() async throws {
            let device = try metalDevice()
            let renderer = try P5MetalRenderer(device: device)
            weak var releasedMesh: P5MetalMesh?
            weak var releasedTexture: P5MetalTexture?
            weak var releasedShader: P5MetalShader?
            do {
                let mesh = try await renderer.makeMesh(P5Mesh.plane())
                let texture = try await renderer.makeTexture(
                    from: testImage(),
                    configuration: P5TextureConfiguration3D(generatesMipmaps: false)
                )
                let source = p5TestShaderSource
                let shader = try await renderer.makeShader(
                    source: source,
                    vertexFunction: "p5Vertex3D",
                    fragmentFunction: "p5Fragment3D"
                )
                releasedMesh = mesh
                releasedTexture = texture
                releasedShader = shader
                #expect(releasedMesh != nil)
                #expect(releasedTexture != nil)
                #expect(releasedShader != nil)
            }
            #expect(releasedMesh == nil)
            #expect(releasedTexture == nil)
            #expect(releasedShader == nil)

            let camera = try P5Camera3D()
            let target = try await renderer.makeRenderTarget(width: 4, height: 4)
            let scene = P5Scene3D(camera: camera, lights: [], instances: [])
            for _ in 0..<100 {
                _ = try await renderer.render(
                    scene,
                    to: target,
                    configuration: P5RenderConfiguration3D(
                        depthMode: .disabled,
                        cullMode: .none
                    )
                )
            }
            let statistics = await renderer.statistics()
            #expect(statistics.submittedFrames == 100)
            #expect(statistics.completedFrames == 100)
            #expect(statistics.lastDrawCallCount == 0)
        }
    }

    private enum P5MetalTestError: String, Error, LocalizedError {
        case injected

        var errorDescription: String? { rawValue }
    }

    private final class P5MetalFactoryState: @unchecked Sendable {
        var libraryCalls = 0
        var bufferCalls = 0
        var samplerCalls = 0
        var textureCalls = 0
    }

    private func metalDevice() throws -> any MTLDevice {
        try #require(MTLCreateSystemDefaultDevice())
    }

    private func makeFactory(device: any MTLDevice) -> P5MetalResourceFactory {
        var factory = P5MetalResourceFactory.system
        factory.makeDevice = { device }
        factory.loadShaderSource = { p5TestShaderSource }
        return factory
    }

    private let p5TestShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct TestVertex {
            float3 position;
            float3 normal;
            float2 textureCoordinate;
            float4 color;
        };

        struct TestOutput {
            float4 position [[position]];
        };

        vertex TestOutput p5Vertex3D(
            uint vertexID [[vertex_id]],
            const device TestVertex *vertices [[buffer(0)]])
        {
            TestOutput output;
            output.position = float4(vertices[vertexID].position, 1.0);
            return output;
        }

        fragment float4 p5Fragment3D(TestOutput input [[stage_in]])
        {
            return float4(1.0);
        }
        """

    private func expectRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
        #expect(try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value)) == value)
    }

    private func testImage() throws -> P5Image {
        try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2,
                height: 2,
                bytes: [
                    255, 0, 0, 255, 0, 255, 0, 255,
                    0, 0, 255, 255, 255, 255, 255, 128,
                ]
            )
        )
    }

    private func makeTexture(
        device: any MTLDevice,
        type: MTLTextureType,
        format: MTLPixelFormat,
        usage: MTLTextureUsage,
        storage: MTLStorageMode,
        sampleCount: Int = 1
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = type
        descriptor.pixelFormat = format
        descriptor.width = 2
        descriptor.height = 2
        descriptor.depth = 1
        descriptor.mipmapLevelCount = 1
        descriptor.sampleCount = sampleCount
        descriptor.arrayLength = 1
        descriptor.usage = usage
        descriptor.storageMode = storage
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    private func invalidLightColors() -> [SIMD3<Float>] {
        var values = invalidFiniteRGBValues()
        for index in 0..<3 {
            var value = SIMD3<Float>(repeating: 1)
            value[index] = -0.01
            values.append(value)
        }
        return values
    }

    private func invalidRGBAValues() -> [SIMD4<Float>] {
        var values = invalidFiniteRGBAValues()
        for index in 0..<4 {
            var low = SIMD4<Float>(repeating: 0.5)
            low[index] = -0.01
            values.append(low)
            var high = SIMD4<Float>(repeating: 0.5)
            high[index] = 1.01
            values.append(high)
        }
        return values
    }

    private func invalidFiniteRGBAValues() -> [SIMD4<Float>] {
        (0..<4).flatMap { index in
            [Float.nan, -.infinity, .infinity].map { invalid in
                var value = SIMD4<Float>(repeating: 0.5)
                value[index] = invalid
                return value
            }
        }
    }

    private func invalidFiniteRGBValues() -> [SIMD3<Float>] {
        (0..<3).flatMap { index in
            [Float.nan, -.infinity, .infinity].map { invalid in
                var value = SIMD3<Float>(repeating: 0.5)
                value[index] = invalid
                return value
            }
        }
    }
#endif
