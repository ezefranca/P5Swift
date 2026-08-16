#if canImport(Metal)
    import CoreGraphics
    import Foundation
    @preconcurrency import Metal
    @preconcurrency import MetalKit
    import QuartzCore
    import simd

    /// Typed failures from P5's Metal-backed 3D renderer.
    public enum P5Metal3DError: Error, Sendable, Hashable, LocalizedError {
        /// No Metal device is available.
        case unavailable
        /// The bundled default shader source could not be loaded.
        case shaderSourceUnavailable
        /// Metal rejected shader source.
        case shaderCompilationFailed(String)
        /// A requested vertex or fragment function is absent.
        case shaderFunctionUnavailable(String)
        /// Metal could not construct a render pipeline.
        case pipelineCreationFailed(String)
        /// Metal could not construct a command queue.
        case commandQueueCreationFailed
        /// Metal could not construct a sampler.
        case samplerCreationFailed
        /// Metal could not allocate a vertex buffer.
        case vertexBufferCreationFailed
        /// Metal could not allocate an index buffer.
        case indexBufferCreationFailed
        /// Metal could not allocate or upload a texture.
        case textureCreationFailed
        /// Metal could not allocate a color render target.
        case renderTargetCreationFailed
        /// Metal could not allocate a depth/stencil target.
        case depthStencilCreationFailed
        /// Metal could not allocate a multisample color target.
        case multisampleCreationFailed
        /// The selected device does not support a requested sample count.
        case unsupportedSampleCount(Int)
        /// A wrapped target has unsupported dimensions, type, usage, or format.
        case invalidRenderTarget
        /// The target format differs from the configured pipeline format.
        case renderTargetFormatMismatch
        /// Render configuration values are invalid.
        case invalidConfiguration
        /// A material contains invalid components.
        case invalidMaterial
        /// A scene light is invalid or the scene exceeds the light limit.
        case invalidLight(Int)
        /// A model matrix cannot produce a finite inverse-transpose normal matrix.
        case nonInvertibleModelMatrix(Int)
        /// The command queue could not create a command buffer.
        case commandBufferCreationFailed
        /// The command buffer could not create a render encoder.
        case commandEncoderCreationFailed
        /// A committed command failed.
        case commandExecutionFailed(status: Int, message: String)
        /// The target cannot be read as an RGBA8 pixel buffer.
        case targetReadbackUnavailable
        /// UIKit/AppKit view pacing values are invalid.
        case invalidFramePacing

        /// A stable diagnostic for logs and user interfaces.
        public var errorDescription: String? {
            switch self {
            case .unavailable: "Metal is unavailable on this device."
            case .shaderSourceUnavailable: "The bundled P5 3D shader source is unavailable."
            case .shaderCompilationFailed(let message):
                "Metal could not compile the 3D shader: \(message)"
            case .shaderFunctionUnavailable(let name):
                "The Metal 3D shader function '\(name)' is unavailable."
            case .pipelineCreationFailed(let message):
                "Metal could not create the 3D render pipeline: \(message)"
            case .commandQueueCreationFailed: "Metal could not create a 3D command queue."
            case .samplerCreationFailed: "Metal could not create a 3D texture sampler."
            case .vertexBufferCreationFailed: "Metal could not allocate the 3D vertex buffer."
            case .indexBufferCreationFailed: "Metal could not allocate the 3D index buffer."
            case .textureCreationFailed: "Metal could not allocate or upload the 3D texture."
            case .renderTargetCreationFailed: "Metal could not allocate the 3D color target."
            case .depthStencilCreationFailed:
                "Metal could not allocate the 3D depth/stencil target."
            case .multisampleCreationFailed:
                "Metal could not allocate the multisample 3D color target."
            case .unsupportedSampleCount(let count):
                "This Metal device does not support sample count \(count)."
            case .invalidRenderTarget: "The supplied Metal render target is incompatible."
            case .renderTargetFormatMismatch:
                "The Metal target and render configuration use different color formats."
            case .invalidConfiguration: "The Metal 3D render configuration is invalid."
            case .invalidMaterial: "The Metal 3D material contains invalid values."
            case .invalidLight(let index): "Metal 3D light \(index) is invalid."
            case .nonInvertibleModelMatrix(let index):
                "Metal 3D instance \(index) has a noninvertible model transform."
            case .commandBufferCreationFailed: "Metal could not create a 3D command buffer."
            case .commandEncoderCreationFailed: "Metal could not create a 3D render encoder."
            case .commandExecutionFailed(_, let message):
                "The Metal 3D command failed: \(message)"
            case .targetReadbackUnavailable:
                "The Metal 3D target cannot be read back as RGBA8 pixels."
            case .invalidFramePacing: "The Metal view frame-pacing configuration is invalid."
            }
        }
    }

    /// Immutable statistics from completed renderer submissions.
    public struct P5MetalRendererStatistics: Sendable, Hashable, Codable {
        /// Frames committed to Metal.
        public let submittedFrames: UInt64
        /// Frames that reached the completed state.
        public let completedFrames: UInt64
        /// Draw calls in the most recently completed frame.
        public let lastDrawCallCount: Int
        /// Triangles in the most recently completed frame.
        public let lastTriangleCount: Int
        /// GPU interval reported by Metal, when supported.
        public let lastGPUTime: TimeInterval?

        /// Creates a statistics snapshot.
        public init(
            submittedFrames: UInt64 = 0,
            completedFrames: UInt64 = 0,
            lastDrawCallCount: Int = 0,
            lastTriangleCount: Int = 0,
            lastGPUTime: TimeInterval? = nil
        ) {
            self.submittedFrames = submittedFrames
            self.completedFrames = completedFrames
            self.lastDrawCallCount = lastDrawCallCount
            self.lastTriangleCount = lastTriangleCount
            self.lastGPUTime = lastGPUTime
        }
    }

    /// A color texture used as an offscreen target or wrapping a drawable texture.
    public final class P5MetalRenderTarget: @unchecked Sendable {
        /// Target width in pixels.
        public let width: Int
        /// Target height in pixels.
        public let height: Int
        /// Target color format.
        public let colorFormat: P5PixelFormat3D
        let texture: any MTLTexture
        let drawable: (any CAMetalDrawable)?

        private init(
            validatedTexture texture: any MTLTexture,
            colorFormat: P5PixelFormat3D,
            drawable: (any CAMetalDrawable)?
        ) {
            width = texture.width
            height = texture.height
            self.colorFormat = colorFormat
            self.texture = texture
            self.drawable = drawable
        }

        /// Wraps an application-owned single-sample render-target texture.
        public convenience init(texture: any MTLTexture) throws {
            guard
                texture.width > 0, texture.height > 0, texture.textureType == .type2D,
                texture.sampleCount == 1, texture.usage.contains(.renderTarget),
                let colorFormat = P5PixelFormat3D(metal: texture.pixelFormat)
            else { throw P5Metal3DError.invalidRenderTarget }
            self.init(validatedTexture: texture, colorFormat: colorFormat, drawable: nil)
        }

        convenience init(texture: any MTLTexture, drawable: (any CAMetalDrawable)?) throws {
            guard
                texture.width > 0, texture.height > 0, texture.textureType == .type2D,
                texture.sampleCount == 1, texture.usage.contains(.renderTarget),
                let colorFormat = P5PixelFormat3D(metal: texture.pixelFormat)
            else { throw P5Metal3DError.invalidRenderTarget }
            self.init(validatedTexture: texture, colorFormat: colorFormat, drawable: drawable)
        }

        /// Reads a shared BGRA8 target into straight-alpha top-left RGBA8 pixels.
        ///
        /// Call only after the corresponding render operation has completed.
        public func pixelBuffer(pixelDensity: CGFloat = 1) throws -> P5PixelBuffer {
            guard
                colorFormat == .bgra8Unorm || colorFormat == .bgra8UnormSRGB,
                texture.storageMode == .shared
            else { throw P5Metal3DError.targetReadbackUnavailable }
            let bytesPerRow = width * 4
            let byteCount = bytesPerRow * height
            let storage = UnsafeMutableRawPointer.allocate(
                byteCount: byteCount,
                alignment: MemoryLayout<UInt8>.alignment
            )
            defer { storage.deallocate() }
            texture.getBytes(
                storage,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
            var bytes = Array(UnsafeRawBufferPointer(start: storage, count: byteCount))
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                bytes.swapAt(offset, offset + 2)
            }
            return P5PixelBuffer(
                width: width,
                height: height,
                pixelDensity: pixelDensity,
                bytes: bytes
            )
        }
    }

    /// Main-actor frame pacing and drawable configuration for an `MTKView`.
    public struct P5MetalViewConfiguration: Sendable, Hashable, Codable {
        /// Preferred display refresh rate.
        public let preferredFramesPerSecond: Int
        /// Whether the view draws only after an explicit request.
        public let drawsOnDemand: Bool
        /// Drawable color format.
        public let colorFormat: P5PixelFormat3D

        /// Creates validated display pacing.
        public init(
            preferredFramesPerSecond: Int = 60,
            drawsOnDemand: Bool = false,
            colorFormat: P5PixelFormat3D = .bgra8Unorm
        ) throws {
            guard (1...240).contains(preferredFramesPerSecond) else {
                throw P5Metal3DError.invalidFramePacing
            }
            self.preferredFramesPerSecond = preferredFramesPerSecond
            self.drawsOnDemand = drawsOnDemand
            self.colorFormat = colorFormat
        }

        /// Applies pacing and drawable policy to a native MetalKit view.
        @MainActor
        public func apply(to view: MTKView, device: any MTLDevice) {
            view.device = device
            view.colorPixelFormat = colorFormat.metal
            view.depthStencilPixelFormat = .invalid
            view.sampleCount = 1
            view.preferredFramesPerSecond = preferredFramesPerSecond
            view.isPaused = drawsOnDemand
            view.enableSetNeedsDisplay = drawsOnDemand
            view.framebufferOnly = false
        }

        /// Wraps the view's current drawable as a render target, or returns `nil` when
        /// no drawable is available.
        @MainActor
        public func renderTarget(from view: MTKView) throws -> P5MetalRenderTarget? {
            guard let drawable = view.currentDrawable else { return nil }
            return try P5MetalRenderTarget(texture: drawable.texture, drawable: drawable)
        }
    }

    struct P5GPUVertex3D {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var textureCoordinate: SIMD2<Float>
        var color: SIMD4<Float>

        init(_ vertex: P5Vertex3D) {
            position = vertex.position.metalFloat3
            normal = vertex.normal.metalFloat3
            textureCoordinate = SIMD2(vertex.textureCoordinate.u, vertex.textureCoordinate.v)
            color = vertex.color
        }
    }

    struct P5GPUUniforms3D {
        var modelMatrix: simd_float4x4
        var viewProjectionMatrix: simd_float4x4
        var normalMatrix: simd_float3x3
        var baseColor: SIMD4<Float>
        var cameraPosition: SIMD4<Float>
        var materialParameters: SIMD4<Float>
        var emissiveColor: SIMD4<Float>
    }

    struct P5GPULight3D {
        var positionAndKind: SIMD4<Float>
        var colorAndIntensity: SIMD4<Float>
        var directionAndRange: SIMD4<Float>
    }

    private struct P5MetalPipelineKey: Hashable {
        let shader: UUID
        let format: P5PixelFormat3D
        let sampleCount: Int
        let blendMode: P5BlendMode3D
        let hasDepth: Bool
        let hasStencil: Bool
    }

    private struct P5MetalDepthKey: Hashable {
        let mode: P5DepthMode3D
        let stencil: P5StencilConfiguration3D?
    }

    struct P5MetalResourceFactory: @unchecked Sendable {
        var makeDevice: () -> (any MTLDevice)?
        var loadShaderSource: () -> String?
        var makeLibrary: (any MTLDevice, String) throws -> any MTLLibrary
        var makeFunction: (any MTLLibrary, String) -> (any MTLFunction)?
        var makeCommandQueue: (any MTLDevice) -> (any MTLCommandQueue)?
        var makePipeline:
            (any MTLDevice, MTLRenderPipelineDescriptor) throws ->
                any MTLRenderPipelineState
        var makeDepthState:
            (any MTLDevice, MTLDepthStencilDescriptor) ->
                (any MTLDepthStencilState)?
        var makeSampler: (any MTLDevice, MTLSamplerDescriptor) -> (any MTLSamplerState)?
        var makeTexture: (any MTLDevice, MTLTextureDescriptor) -> (any MTLTexture)?
        var supportsSampleCount: (any MTLDevice, Int) -> Bool
        var makeImageTexture:
            (any MTLDevice, CGImage, P5TextureConfiguration3D) throws ->
                any MTLTexture
        var makeBuffer: (any MTLDevice, UnsafeRawPointer, Int) -> (any MTLBuffer)?

        static let system = Self(
            makeDevice: { MTLCreateSystemDefaultDevice() },
            loadShaderSource: {
                shaderSource(
                    at: Bundle.module.url(
                        forResource: "P5Renderer3D",
                        withExtension: "metal"
                    )
                )
            },
            makeLibrary: { device, source in
                try device.makeLibrary(source: source, options: nil)
            },
            makeFunction: { library, name in library.makeFunction(name: name) },
            makeCommandQueue: { $0.makeCommandQueue() },
            makePipeline: { try $0.makeRenderPipelineState(descriptor: $1) },
            makeDepthState: { $0.makeDepthStencilState(descriptor: $1) },
            makeSampler: { $0.makeSamplerState(descriptor: $1) },
            makeTexture: { $0.makeTexture(descriptor: $1) },
            supportsSampleCount: { $0.supportsTextureSampleCount($1) },
            makeImageTexture: { device, image, configuration in
                let loader = MTKTextureLoader(device: device)
                return try loader.newTexture(
                    cgImage: image,
                    options: [
                        .SRGB: false,
                        .generateMipmaps: configuration.generatesMipmaps,
                        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                    ]
                )
            },
            makeBuffer: { device, bytes, count in
                device.makeBuffer(bytes: bytes, length: count, options: .storageModeShared)
            }
        )

        static func shaderSource(at url: URL?) -> String? {
            guard let url else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    struct P5MetalExecutionHooks: @unchecked Sendable {
        var makeCommandBuffer: (any MTLCommandQueue) -> (any MTLCommandBuffer)?
        var makeEncoder:
            (any MTLCommandBuffer, MTLRenderPassDescriptor) ->
                (any MTLRenderCommandEncoder)?
        var waitForCompletion: @Sendable (any MTLCommandBuffer) async throws -> TimeInterval?

        static let system = Self(
            makeCommandBuffer: { $0.makeCommandBuffer() },
            makeEncoder: { $0.makeRenderCommandEncoder(descriptor: $1) },
            waitForCompletion: { commandBuffer in
                try await withCheckedThrowingContinuation { continuation in
                    commandBuffer.addCompletedHandler { completed in
                        continuation.resume(
                            with: Result {
                                try completedGPUTime(
                                    status: completed.status,
                                    message: completed.error?.localizedDescription,
                                    startTime: completed.gpuStartTime,
                                    endTime: completed.gpuEndTime
                                )
                            }
                        )
                    }
                    commandBuffer.commit()
                }
            }
        )

        static func completedGPUTime(
            status: MTLCommandBufferStatus,
            message: String?,
            startTime: TimeInterval,
            endTime: TimeInterval
        ) throws -> TimeInterval? {
            guard status == .completed else {
                throw P5Metal3DError.commandExecutionFailed(
                    status: Int(status.rawValue),
                    message: message ?? "The command buffer did not complete."
                )
            }
            return endTime > startTime ? endTime - startTime : nil
        }
    }

    /// Actor-owned Metal renderer with explicit resource creation and no CPU fallback.
    public actor P5MetalRenderer {
        /// Maximum lights accepted by the bundled shader ABI.
        public static let maximumLightCount = 8

        /// Whether this process can create a default Metal device.
        public static var isAvailable: Bool { MTLCreateSystemDefaultDevice() != nil }

        /// Native device name for diagnostics.
        public nonisolated let deviceName: String

        private let device: any MTLDevice
        private let commandQueue: any MTLCommandQueue
        private let defaultShader: P5MetalShader
        private let fallbackTexture: any MTLTexture
        private let fallbackSampler: any MTLSamplerState
        private let resourceFactory: P5MetalResourceFactory
        private let executionHooks: P5MetalExecutionHooks
        private var pipelines: [P5MetalPipelineKey: any MTLRenderPipelineState] = [:]
        private var depthStates: [P5MetalDepthKey: any MTLDepthStencilState] = [:]
        private var statisticsValue = P5MetalRendererStatistics()

        /// Creates a renderer using the system's default Metal device.
        public init() throws {
            try self.init(resourceFactory: .system, executionHooks: .system)
        }

        /// Creates a renderer on an explicitly selected Metal device.
        public init(device: any MTLDevice) throws {
            var factory = P5MetalResourceFactory.system
            factory.makeDevice = { device }
            try self.init(resourceFactory: factory, executionHooks: .system)
        }

        init(
            resourceFactory: P5MetalResourceFactory,
            executionHooks: P5MetalExecutionHooks
        ) throws {
            guard let device = resourceFactory.makeDevice() else {
                throw P5Metal3DError.unavailable
            }
            guard let source = resourceFactory.loadShaderSource() else {
                throw P5Metal3DError.shaderSourceUnavailable
            }
            let library: any MTLLibrary
            do {
                library = try resourceFactory.makeLibrary(device, source)
            } catch {
                throw P5Metal3DError.shaderCompilationFailed(error.localizedDescription)
            }
            guard let vertex = resourceFactory.makeFunction(library, "p5Vertex3D") else {
                throw P5Metal3DError.shaderFunctionUnavailable("p5Vertex3D")
            }
            guard let fragment = resourceFactory.makeFunction(library, "p5Fragment3D") else {
                throw P5Metal3DError.shaderFunctionUnavailable("p5Fragment3D")
            }
            guard let queue = resourceFactory.makeCommandQueue(device) else {
                throw P5Metal3DError.commandQueueCreationFailed
            }
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .nearest
            samplerDescriptor.magFilter = .nearest
            guard let sampler = resourceFactory.makeSampler(device, samplerDescriptor) else {
                throw P5Metal3DError.samplerCreationFailed
            }
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: 1,
                height: 1,
                mipmapped: false
            )
            textureDescriptor.usage = .shaderRead
            textureDescriptor.storageMode = .shared
            guard let texture = resourceFactory.makeTexture(device, textureDescriptor) else {
                throw P5Metal3DError.textureCreationFailed
            }
            var white = SIMD4<UInt8>(repeating: 255)
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: &white,
                bytesPerRow: 4
            )

            deviceName = device.name
            self.device = device
            commandQueue = queue
            defaultShader = P5MetalShader(vertexFunction: vertex, fragmentFunction: fragment)
            fallbackTexture = texture
            fallbackSampler = sampler
            self.resourceFactory = resourceFactory
            self.executionHooks = executionHooks
        }

        /// Current immutable execution statistics.
        public func statistics() -> P5MetalRendererStatistics { statisticsValue }

        /// Compiles custom source using the documented P5 vertex/fragment buffer ABI.
        public func makeShader(
            source: String,
            vertexFunction: String,
            fragmentFunction: String
        ) throws -> P5MetalShader {
            guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw P5Metal3DError.shaderSourceUnavailable
            }
            let library: any MTLLibrary
            do {
                library = try resourceFactory.makeLibrary(device, source)
            } catch {
                throw P5Metal3DError.shaderCompilationFailed(error.localizedDescription)
            }
            guard let vertex = resourceFactory.makeFunction(library, vertexFunction) else {
                throw P5Metal3DError.shaderFunctionUnavailable(vertexFunction)
            }
            guard let fragment = resourceFactory.makeFunction(library, fragmentFunction) else {
                throw P5Metal3DError.shaderFunctionUnavailable(fragmentFunction)
            }
            return P5MetalShader(vertexFunction: vertex, fragmentFunction: fragment)
        }

        /// Uploads immutable vertex and index buffers.
        public func makeMesh(_ mesh: P5Mesh) throws -> P5MetalMesh {
            var vertices = mesh.vertices.map(P5GPUVertex3D.init)
            let vertexByteCount = MemoryLayout<P5GPUVertex3D>.stride * vertices.count
            let vertexBuffer = withUnsafePointer(to: &vertices[0]) { pointer in
                resourceFactory.makeBuffer(device, pointer, vertexByteCount)
            }
            guard let vertexBuffer else { throw P5Metal3DError.vertexBufferCreationFailed }
            var indices = mesh.indices
            let indexByteCount = MemoryLayout<UInt32>.stride * indices.count
            let indexBuffer = withUnsafePointer(to: &indices[0]) { pointer in
                resourceFactory.makeBuffer(device, pointer, indexByteCount)
            }
            guard let indexBuffer else { throw P5Metal3DError.indexBufferCreationFailed }
            return P5MetalMesh(mesh: mesh, vertexBuffer: vertexBuffer, indexBuffer: indexBuffer)
        }

        /// Uploads an immutable P5 image and creates its sampler.
        public func makeTexture(
            from image: P5Image,
            configuration: P5TextureConfiguration3D = P5TextureConfiguration3D()
        ) throws -> P5MetalTexture {
            let texture: any MTLTexture
            do {
                texture = try resourceFactory.makeImageTexture(
                    device,
                    image.cgImage,
                    configuration
                )
            } catch {
                throw P5Metal3DError.textureCreationFailed
            }
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = configuration.usesLinearFiltering ? .linear : .nearest
            descriptor.magFilter = configuration.usesLinearFiltering ? .linear : .nearest
            descriptor.mipFilter = configuration.generatesMipmaps ? .linear : .notMipmapped
            descriptor.sAddressMode = configuration.repeats ? .repeat : .clampToEdge
            descriptor.tAddressMode = configuration.repeats ? .repeat : .clampToEdge
            guard let sampler = resourceFactory.makeSampler(device, descriptor) else {
                throw P5Metal3DError.samplerCreationFailed
            }
            return P5MetalTexture(
                texture: texture,
                sampler: sampler,
                hasMipmaps: configuration.generatesMipmaps
            )
        }

        /// Allocates a shared single-sample offscreen color target.
        public func makeRenderTarget(
            width: Int,
            height: Int,
            colorFormat: P5PixelFormat3D = .bgra8Unorm
        ) throws -> P5MetalRenderTarget {
            guard width > 0, height > 0 else { throw P5Metal3DError.invalidRenderTarget }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: colorFormat.metal,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let texture = resourceFactory.makeTexture(device, descriptor) else {
                throw P5Metal3DError.renderTargetCreationFailed
            }
            return try P5MetalRenderTarget(texture: texture)
        }

        /// Encodes, commits, presents when needed, and awaits one complete render pass.
        @discardableResult
        public func render(
            _ scene: P5Scene3D,
            to target: P5MetalRenderTarget,
            configuration: P5RenderConfiguration3D = .standard
        ) async throws -> P5MetalRendererStatistics {
            try Task.checkCancellation()
            guard target.colorFormat == configuration.colorFormat else {
                throw P5Metal3DError.renderTargetFormatMismatch
            }
            guard resourceFactory.supportsSampleCount(device, configuration.sampleCount) else {
                throw P5Metal3DError.unsupportedSampleCount(configuration.sampleCount)
            }
            let aspect = Float(target.width) / Float(target.height)
            let viewProjection =
                try scene.camera.projection.matrix(aspectRatio: aspect).simdMatrix
                * scene.camera.viewMatrix.simdMatrix
            let lights = try Self.gpuLights(scene.lights)
            var prepared: [(P5MeshInstance3D, P5GPUUniforms3D)] = []
            for (index, instance) in scene.instances.enumerated() {
                let model = instance.modelMatrix.simdMatrix
                let upper = simd_float3x3(
                    SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z),
                    SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z),
                    SIMD3(model.columns.2.x, model.columns.2.y, model.columns.2.z)
                )
                let determinant = simd_determinant(upper)
                guard determinant.isFinite, abs(determinant) > Float.ulpOfOne else {
                    throw P5Metal3DError.nonInvertibleModelMatrix(index)
                }
                let material = instance.material
                prepared.append(
                    (
                        instance,
                        P5GPUUniforms3D(
                            modelMatrix: model,
                            viewProjectionMatrix: viewProjection,
                            normalMatrix: simd_transpose(simd_inverse(upper)),
                            baseColor: material.baseColor,
                            cameraPosition: SIMD4(scene.camera.position.metalFloat3, 1),
                            materialParameters: SIMD4(
                                material.metallic,
                                material.roughness,
                                material.texture == nil ? 0 : 1,
                                material.isUnlit ? 1 : 0
                            ),
                            emissiveColor: SIMD4(material.emissiveColor, 0)
                        )
                    )
                )
            }

            let attachments = try makeAttachments(target: target, configuration: configuration)
            let pass = attachments.pass
            guard let commandBuffer = executionHooks.makeCommandBuffer(commandQueue) else {
                throw P5Metal3DError.commandBufferCreationFailed
            }
            guard let encoder = executionHooks.makeEncoder(commandBuffer, pass) else {
                throw P5Metal3DError.commandEncoderCreationFailed
            }
            var endedEncoding = false
            defer {
                if endedEncoding == false { encoder.endEncoding() }
            }
            encoder.setCullMode(configuration.cullMode.metal)
            encoder.setFrontFacing(configuration.frontFace.metal)
            if let stencil = configuration.stencil {
                encoder.setStencilReferenceValue(stencil.referenceValue)
            }
            let depthState = try depthState(configuration)
            encoder.setDepthStencilState(depthState)

            var gpuLights =
                lights.isEmpty
                ? [
                    P5GPULight3D(
                        positionAndKind: .zero, colorAndIntensity: .zero, directionAndRange: .zero)
                ]
                : lights
            var lightCount = UInt32(lights.count)
            let lightByteCount = MemoryLayout<P5GPULight3D>.stride * gpuLights.count
            withUnsafePointer(to: &gpuLights[0]) { pointer in
                encoder.setFragmentBytes(pointer, length: lightByteCount, index: 2)
            }
            encoder.setFragmentBytes(&lightCount, length: MemoryLayout<UInt32>.size, index: 3)

            var triangleCount = 0
            for (instance, initialUniforms) in prepared {
                let shader = instance.material.shader ?? defaultShader
                let pipeline = try pipeline(
                    shader: shader,
                    configuration: configuration
                )
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(instance.mesh.vertexBuffer, offset: 0, index: 0)
                var uniforms = initialUniforms
                encoder.setVertexBytes(
                    &uniforms,
                    length: MemoryLayout<P5GPUUniforms3D>.stride,
                    index: 1
                )
                encoder.setFragmentBytes(
                    &uniforms,
                    length: MemoryLayout<P5GPUUniforms3D>.stride,
                    index: 1
                )
                encoder.setFragmentTexture(
                    instance.material.texture?.texture ?? fallbackTexture,
                    index: 0
                )
                encoder.setFragmentSamplerState(
                    instance.material.texture?.sampler ?? fallbackSampler,
                    index: 0
                )
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: instance.mesh.indexCount,
                    indexType: .uint32,
                    indexBuffer: instance.mesh.indexBuffer,
                    indexBufferOffset: 0
                )
                triangleCount += instance.mesh.indexCount / 3
            }
            encoder.endEncoding()
            endedEncoding = true
            if let drawable = target.drawable { commandBuffer.present(drawable) }
            try Task.checkCancellation()
            statisticsValue = P5MetalRendererStatistics(
                submittedFrames: statisticsValue.submittedFrames + 1,
                completedFrames: statisticsValue.completedFrames,
                lastDrawCallCount: statisticsValue.lastDrawCallCount,
                lastTriangleCount: statisticsValue.lastTriangleCount,
                lastGPUTime: statisticsValue.lastGPUTime
            )
            let gpuTime = try await executionHooks.waitForCompletion(commandBuffer)
            try Task.checkCancellation()
            statisticsValue = P5MetalRendererStatistics(
                submittedFrames: statisticsValue.submittedFrames,
                completedFrames: statisticsValue.completedFrames + 1,
                lastDrawCallCount: prepared.count,
                lastTriangleCount: triangleCount,
                lastGPUTime: gpuTime
            )
            _ = attachments.retainedTextures
            return statisticsValue
        }

        private func pipeline(
            shader: P5MetalShader,
            configuration: P5RenderConfiguration3D
        ) throws -> any MTLRenderPipelineState {
            let key = P5MetalPipelineKey(
                shader: shader.identifier,
                format: configuration.colorFormat,
                sampleCount: configuration.sampleCount,
                blendMode: configuration.blendMode,
                hasDepth: configuration.depthMode != .disabled,
                hasStencil: configuration.stencil != nil
            )
            if let existing = pipelines[key] { return existing }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = shader.vertexFunction
            descriptor.fragmentFunction = shader.fragmentFunction
            descriptor.rasterSampleCount = configuration.sampleCount
            descriptor.colorAttachments[0].pixelFormat = configuration.colorFormat.metal
            configuration.blendMode.apply(to: descriptor.colorAttachments[0])
            if configuration.depthMode != .disabled || configuration.stencil != nil {
                let format: MTLPixelFormat =
                    configuration.stencil == nil
                    ? .depth32Float : .depth32Float_stencil8
                descriptor.depthAttachmentPixelFormat = format
                if configuration.stencil != nil { descriptor.stencilAttachmentPixelFormat = format }
            }
            let created: any MTLRenderPipelineState
            do {
                created = try resourceFactory.makePipeline(device, descriptor)
            } catch {
                throw P5Metal3DError.pipelineCreationFailed(error.localizedDescription)
            }
            pipelines[key] = created
            return created
        }

        private func depthState(_ configuration: P5RenderConfiguration3D) throws
            -> (any MTLDepthStencilState)?
        {
            guard configuration.depthMode != .disabled || configuration.stencil != nil else {
                return nil
            }
            let key = P5MetalDepthKey(mode: configuration.depthMode, stencil: configuration.stencil)
            if let existing = depthStates[key] { return existing }
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = configuration.depthMode == .disabled ? .always : .less
            descriptor.isDepthWriteEnabled = configuration.depthMode == .readWrite
            if let stencil = configuration.stencil {
                let face = MTLStencilDescriptor()
                face.stencilCompareFunction = stencil.compare.metal
                face.stencilFailureOperation = stencil.stencilFailure.metal
                face.depthFailureOperation = stencil.depthFailure.metal
                face.depthStencilPassOperation = stencil.pass.metal
                face.readMask = stencil.readMask
                face.writeMask = stencil.writeMask
                descriptor.frontFaceStencil = face
                descriptor.backFaceStencil = face
            }
            guard let state = resourceFactory.makeDepthState(device, descriptor) else {
                throw P5Metal3DError.depthStencilCreationFailed
            }
            depthStates[key] = state
            return state
        }

        private func makeAttachments(
            target: P5MetalRenderTarget,
            configuration: P5RenderConfiguration3D
        ) throws -> (pass: MTLRenderPassDescriptor, retainedTextures: [any MTLTexture]) {
            let pass = MTLRenderPassDescriptor()
            let color = pass.colorAttachments[0]
            color?.loadAction = .clear
            color?.clearColor = MTLClearColor(
                red: Double(configuration.clearColor.x),
                green: Double(configuration.clearColor.y),
                blue: Double(configuration.clearColor.z),
                alpha: Double(configuration.clearColor.w)
            )
            var retained: [any MTLTexture] = []
            if configuration.sampleCount == 1 {
                color?.texture = target.texture
                color?.storeAction = .store
            } else {
                let descriptor = MTLTextureDescriptor()
                descriptor.textureType = .type2DMultisample
                descriptor.pixelFormat = target.texture.pixelFormat
                descriptor.width = target.width
                descriptor.height = target.height
                descriptor.sampleCount = configuration.sampleCount
                descriptor.storageMode = .private
                descriptor.usage = .renderTarget
                guard let multisample = resourceFactory.makeTexture(device, descriptor) else {
                    throw P5Metal3DError.multisampleCreationFailed
                }
                color?.texture = multisample
                color?.resolveTexture = target.texture
                color?.storeAction = .multisampleResolve
                retained.append(multisample)
            }

            if configuration.depthMode != .disabled || configuration.stencil != nil {
                let descriptor = MTLTextureDescriptor()
                descriptor.textureType =
                    configuration.sampleCount == 1
                    ? .type2D : .type2DMultisample
                descriptor.pixelFormat =
                    configuration.stencil == nil
                    ? .depth32Float : .depth32Float_stencil8
                descriptor.width = target.width
                descriptor.height = target.height
                descriptor.sampleCount = configuration.sampleCount
                descriptor.storageMode = .private
                descriptor.usage = .renderTarget
                guard let depth = resourceFactory.makeTexture(device, descriptor) else {
                    throw P5Metal3DError.depthStencilCreationFailed
                }
                pass.depthAttachment.texture = depth
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.storeAction = .dontCare
                pass.depthAttachment.clearDepth = 1
                if configuration.stencil != nil {
                    pass.stencilAttachment.texture = depth
                    pass.stencilAttachment.loadAction = .clear
                    pass.stencilAttachment.storeAction = .dontCare
                    pass.stencilAttachment.clearStencil = 0
                }
                retained.append(depth)
            }
            return (pass, retained)
        }

        static func gpuLights(_ lights: [P5Light3D]) throws -> [P5GPULight3D] {
            guard lights.count <= maximumLightCount else {
                throw P5Metal3DError.invalidLight(maximumLightCount)
            }
            return try lights.enumerated().map { index, light in
                switch light {
                case .ambient(let color, let intensity):
                    guard validColor(color), validIntensity(intensity) else {
                        throw P5Metal3DError.invalidLight(index)
                    }
                    return P5GPULight3D(
                        positionAndKind: SIMD4(0, 0, 0, 0),
                        colorAndIntensity: SIMD4(color, intensity),
                        directionAndRange: .zero
                    )
                case .directional(let direction, let color, let intensity):
                    let vector = direction.metalFloat3
                    let lengthSquared = simd_length_squared(vector)
                    guard
                        vector.allFinite, lengthSquared > 0, validColor(color),
                        validIntensity(intensity)
                    else { throw P5Metal3DError.invalidLight(index) }
                    return P5GPULight3D(
                        positionAndKind: SIMD4(0, 0, 0, 1),
                        colorAndIntensity: SIMD4(color, intensity),
                        directionAndRange: SIMD4(simd_normalize(vector), 0)
                    )
                case .point(let position, let color, let intensity, let range):
                    guard
                        position.metalFloat3.allFinite, validColor(color),
                        validIntensity(intensity), range.isFinite, range > 0
                    else { throw P5Metal3DError.invalidLight(index) }
                    return P5GPULight3D(
                        positionAndKind: SIMD4(position.metalFloat3, 2),
                        colorAndIntensity: SIMD4(color, intensity),
                        directionAndRange: SIMD4(0, 0, 0, range)
                    )
                }
            }
        }

        private static func validColor(_ color: SIMD3<Float>) -> Bool {
            color.allFinite && color.x >= 0 && color.y >= 0 && color.z >= 0
        }

        private static func validIntensity(_ intensity: Float) -> Bool {
            intensity.isFinite && intensity >= 0
        }
    }

    extension P5Matrix4x4 {
        var simdMatrix: simd_float4x4 {
            simd_float4x4(columns: (column0, column1, column2, column3))
        }
    }

    extension P5Vector {
        var metalFloat3: SIMD3<Float> {
            SIMD3(Float(x), Float(y), Float(z))
        }
    }

    extension SIMD3 where Scalar == Float {
        var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }

    extension P5CullMode3D {
        var metal: MTLCullMode {
            switch self {
            case .none: .none
            case .back: .back
            case .front: .front
            }
        }
    }

    extension P5Winding3D {
        var metal: MTLWinding {
            switch self {
            case .counterClockwise: .counterClockwise
            case .clockwise: .clockwise
            }
        }
    }

    extension P5BlendMode3D {
        func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
            guard let attachment else { return }
            switch self {
            case .opaque:
                attachment.isBlendingEnabled = false
            case .alpha:
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .additive:
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .one
            }
        }
    }

    extension P5StencilCompare3D {
        var metal: MTLCompareFunction {
            switch self {
            case .always: .always
            case .equal: .equal
            case .notEqual: .notEqual
            case .less: .less
            case .lessEqual: .lessEqual
            case .greater: .greater
            case .greaterEqual: .greaterEqual
            case .never: .never
            }
        }
    }

    extension P5StencilOperation3D {
        var metal: MTLStencilOperation {
            switch self {
            case .keep: .keep
            case .zero: .zero
            case .replace: .replace
            case .incrementClamp: .incrementClamp
            case .decrementClamp: .decrementClamp
            case .invert: .invert
            }
        }
    }
#endif
