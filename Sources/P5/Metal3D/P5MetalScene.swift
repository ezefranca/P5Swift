#if canImport(Metal)
    import Foundation
    @preconcurrency import Metal

    /// Blending applied while a 3D instance writes to the color target.
    public enum P5BlendMode3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// Replace destination color and alpha.
        case opaque
        /// Standard source-alpha compositing.
        case alpha
        /// Add source color to destination color.
        case additive
    }

    /// Depth-buffer behavior for one render pass.
    public enum P5DepthMode3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// Do not test or write depth.
        case disabled
        /// Test depth while preserving the existing depth target.
        case readOnly
        /// Test and write nearest depth.
        case readWrite
    }

    /// Triangle faces removed before rasterization.
    public enum P5CullMode3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// Rasterize both triangle faces.
        case none
        /// Remove back-facing triangles.
        case back
        /// Remove front-facing triangles.
        case front
    }

    /// Winding that identifies a triangle's front face.
    public enum P5Winding3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// Counterclockwise vertices face forward.
        case counterClockwise
        /// Clockwise vertices face forward.
        case clockwise
    }

    /// Comparison used by a stencil test.
    public enum P5StencilCompare3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// The stencil test always passes.
        case always
        /// Stored and reference values must be equal.
        case equal
        /// Stored and reference values must differ.
        case notEqual
        /// The reference must be less than the stored value.
        case less
        /// The reference must be less than or equal to the stored value.
        case lessEqual
        /// The reference must be greater than the stored value.
        case greater
        /// The reference must be greater than or equal to the stored value.
        case greaterEqual
        /// The stencil test never passes.
        case never
    }

    /// Operation applied to a stencil value after testing.
    public enum P5StencilOperation3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// Preserve the existing value.
        case keep
        /// Store zero.
        case zero
        /// Store the reference value.
        case replace
        /// Increment and clamp at the maximum value.
        case incrementClamp
        /// Decrement and clamp at zero.
        case decrementClamp
        /// Bitwise-invert the existing value.
        case invert
    }

    /// Front-and-back stencil state for one render pass.
    public struct P5StencilConfiguration3D: Sendable, Hashable, Codable {
        /// Stencil comparison.
        public let compare: P5StencilCompare3D
        /// Operation when the stencil test fails.
        public let stencilFailure: P5StencilOperation3D
        /// Operation when stencil passes and depth fails.
        public let depthFailure: P5StencilOperation3D
        /// Operation when both tests pass.
        public let pass: P5StencilOperation3D
        /// Reference value compared with stored stencil.
        public let referenceValue: UInt32
        /// Bits available to reads.
        public let readMask: UInt32
        /// Bits available to writes.
        public let writeMask: UInt32

        /// Creates stencil state with explicit masks and operations.
        public init(
            compare: P5StencilCompare3D = .always,
            stencilFailure: P5StencilOperation3D = .keep,
            depthFailure: P5StencilOperation3D = .keep,
            pass: P5StencilOperation3D = .replace,
            referenceValue: UInt32 = 1,
            readMask: UInt32 = .max,
            writeMask: UInt32 = .max
        ) {
            self.compare = compare
            self.stencilFailure = stencilFailure
            self.depthFailure = depthFailure
            self.pass = pass
            self.referenceValue = referenceValue
            self.readMask = readMask
            self.writeMask = writeMask
        }
    }

    /// Pixel formats supported by p5.swift 3D render targets.
    public enum P5PixelFormat3D: String, Sendable, Hashable, Codable, CaseIterable {
        /// Eight-bit normalized BGRA.
        case bgra8Unorm
        /// Eight-bit normalized sRGB BGRA.
        case bgra8UnormSRGB
        /// Sixteen-bit floating-point RGBA for extended-range rendering.
        case rgba16Float

        var metal: MTLPixelFormat {
            switch self {
            case .bgra8Unorm: .bgra8Unorm
            case .bgra8UnormSRGB: .bgra8Unorm_srgb
            case .rgba16Float: .rgba16Float
            }
        }

        init?(metal: MTLPixelFormat) {
            switch metal {
            case .bgra8Unorm: self = .bgra8Unorm
            case .bgra8Unorm_srgb: self = .bgra8UnormSRGB
            case .rgba16Float: self = .rgba16Float
            default: return nil
            }
        }
    }

    /// Validated render-pass state shared across scene instances.
    public struct P5RenderConfiguration3D: Sendable, Hashable, Codable {
        /// Color format expected by the target and render pipeline.
        public let colorFormat: P5PixelFormat3D
        /// Multisample count; `1` disables MSAA.
        public let sampleCount: Int
        /// Color used to clear the target.
        public let clearColor: SIMD4<Float>
        /// Depth behavior.
        public let depthMode: P5DepthMode3D
        /// Optional stencil behavior.
        public let stencil: P5StencilConfiguration3D?
        /// Triangle culling.
        public let cullMode: P5CullMode3D
        /// Front-face winding.
        public let frontFace: P5Winding3D
        /// Color blending.
        public let blendMode: P5BlendMode3D

        /// A one-sample opaque pass with depth writes and back-face culling.
        public static let standard = Self(
            uncheckedColorFormat: .bgra8Unorm,
            sampleCount: 1,
            clearColor: SIMD4(0, 0, 0, 1),
            depthMode: .readWrite,
            stencil: nil,
            cullMode: .back,
            frontFace: .counterClockwise,
            blendMode: .opaque
        )

        /// Creates validated render state.
        public init(
            colorFormat: P5PixelFormat3D = .bgra8Unorm,
            sampleCount: Int = 1,
            clearColor: SIMD4<Float> = SIMD4(0, 0, 0, 1),
            depthMode: P5DepthMode3D = .readWrite,
            stencil: P5StencilConfiguration3D? = nil,
            cullMode: P5CullMode3D = .back,
            frontFace: P5Winding3D = .counterClockwise,
            blendMode: P5BlendMode3D = .opaque
        ) throws {
            guard [1, 2, 4, 8].contains(sampleCount), Self.validColor(clearColor) else {
                throw P5Metal3DError.invalidConfiguration
            }
            self.colorFormat = colorFormat
            self.sampleCount = sampleCount
            self.clearColor = clearColor
            self.depthMode = depthMode
            self.stencil = stencil
            self.cullMode = cullMode
            self.frontFace = frontFace
            self.blendMode = blendMode
        }

        private init(
            uncheckedColorFormat colorFormat: P5PixelFormat3D,
            sampleCount: Int,
            clearColor: SIMD4<Float>,
            depthMode: P5DepthMode3D,
            stencil: P5StencilConfiguration3D?,
            cullMode: P5CullMode3D,
            frontFace: P5Winding3D,
            blendMode: P5BlendMode3D
        ) {
            self.colorFormat = colorFormat
            self.sampleCount = sampleCount
            self.clearColor = clearColor
            self.depthMode = depthMode
            self.stencil = stencil
            self.cullMode = cullMode
            self.frontFace = frontFace
            self.blendMode = blendMode
        }

        /// Decodes only valid render state.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                colorFormat: container.decode(P5PixelFormat3D.self, forKey: .colorFormat),
                sampleCount: container.decode(Int.self, forKey: .sampleCount),
                clearColor: container.decode(SIMD4<Float>.self, forKey: .clearColor),
                depthMode: container.decode(P5DepthMode3D.self, forKey: .depthMode),
                stencil: container.decodeIfPresent(
                    P5StencilConfiguration3D.self,
                    forKey: .stencil
                ),
                cullMode: container.decode(P5CullMode3D.self, forKey: .cullMode),
                frontFace: container.decode(P5Winding3D.self, forKey: .frontFace),
                blendMode: container.decode(P5BlendMode3D.self, forKey: .blendMode)
            )
        }

        private static func validColor(_ color: SIMD4<Float>) -> Bool {
            color.x.isFinite && color.y.isFinite && color.z.isFinite && color.w.isFinite
                && color.x >= 0 && color.x <= 1 && color.y >= 0 && color.y <= 1
                && color.z >= 0 && color.z <= 1 && color.w >= 0 && color.w <= 1
        }
    }

    /// One light evaluated by the default Metal fragment shader.
    public enum P5Light3D: Sendable, Hashable, Codable {
        /// Uniform light independent of position and direction.
        case ambient(color: SIMD3<Float>, intensity: Float)
        /// Light arriving along a world-space direction.
        case directional(direction: P5Vector, color: SIMD3<Float>, intensity: Float)
        /// Light emitted from a position and attenuated to a finite range.
        case point(position: P5Vector, color: SIMD3<Float>, intensity: Float, range: Float)
    }

    /// GPU texture filtering and edge behavior.
    public struct P5TextureConfiguration3D: Sendable, Hashable, Codable {
        /// Linear rather than nearest-neighbor filtering.
        public let usesLinearFiltering: Bool
        /// Repeat rather than clamp texture coordinates outside `0...1`.
        public let repeats: Bool
        /// Generate mipmap levels after upload.
        public let generatesMipmaps: Bool

        /// Creates texture sampling and upload behavior.
        public init(
            usesLinearFiltering: Bool = true,
            repeats: Bool = false,
            generatesMipmaps: Bool = true
        ) {
            self.usesLinearFiltering = usesLinearFiltering
            self.repeats = repeats
            self.generatesMipmaps = generatesMipmaps
        }
    }

    /// Immutable GPU vertex and index buffers created by ``P5MetalRenderer``.
    public final class P5MetalMesh: @unchecked Sendable {
        /// Number of uploaded vertices.
        public let vertexCount: Int
        /// Number of uploaded indices.
        public let indexCount: Int
        /// Model-space bounds copied from the source mesh.
        public let bounds: P5Bounds3D
        let vertexBuffer: any MTLBuffer
        let indexBuffer: any MTLBuffer

        init(mesh: P5Mesh, vertexBuffer: any MTLBuffer, indexBuffer: any MTLBuffer) {
            vertexCount = mesh.vertices.count
            indexCount = mesh.indices.count
            bounds = mesh.bounds
            self.vertexBuffer = vertexBuffer
            self.indexBuffer = indexBuffer
        }
    }

    /// Immutable Metal texture created or wrapped by ``P5MetalRenderer``.
    public final class P5MetalTexture: @unchecked Sendable {
        /// Raster width.
        public let width: Int
        /// Raster height.
        public let height: Int
        /// Whether mipmaps were generated during upload.
        public let hasMipmaps: Bool
        let texture: any MTLTexture
        let sampler: any MTLSamplerState

        init(texture: any MTLTexture, sampler: any MTLSamplerState, hasMipmaps: Bool) {
            width = texture.width
            height = texture.height
            self.texture = texture
            self.sampler = sampler
            self.hasMipmaps = hasMipmaps
        }
    }

    /// Compiled vertex and fragment entry points compatible with the P5 3D ABI.
    public final class P5MetalShader: @unchecked Sendable {
        /// Vertex entry-point name.
        public let vertexFunctionName: String
        /// Fragment entry-point name.
        public let fragmentFunctionName: String
        let identifier = UUID()
        let vertexFunction: any MTLFunction
        let fragmentFunction: any MTLFunction

        init(vertexFunction: any MTLFunction, fragmentFunction: any MTLFunction) {
            vertexFunctionName = vertexFunction.name
            fragmentFunctionName = fragmentFunction.name
            self.vertexFunction = vertexFunction
            self.fragmentFunction = fragmentFunction
        }
    }

    /// Surface values consumed by the default P5 Metal fragment shader.
    public struct P5Material3D: @unchecked Sendable {
        /// Base linear RGBA multiplier.
        public let baseColor: SIMD4<Float>
        /// Emissive linear RGB contribution.
        public let emissiveColor: SIMD3<Float>
        /// Metallic value in `0...1` reserved for compatible custom shaders.
        public let metallic: Float
        /// Perceptual roughness in `0...1`.
        public let roughness: Float
        /// Whether lighting is bypassed.
        public let isUnlit: Bool
        /// Optional sampled color texture.
        public let texture: P5MetalTexture?
        /// Optional custom shader; `nil` selects the bundled shader.
        public let shader: P5MetalShader?

        /// Creates a validated material.
        public init(
            baseColor: SIMD4<Float> = SIMD4(repeating: 1),
            emissiveColor: SIMD3<Float> = .zero,
            metallic: Float = 0,
            roughness: Float = 0.5,
            isUnlit: Bool = false,
            texture: P5MetalTexture? = nil,
            shader: P5MetalShader? = nil
        ) throws {
            guard
                Self.finite(baseColor), Self.finite(emissiveColor), metallic.isFinite,
                (0...1).contains(metallic), roughness.isFinite, (0...1).contains(roughness)
            else { throw P5Metal3DError.invalidMaterial }
            self.baseColor = baseColor
            self.emissiveColor = emissiveColor
            self.metallic = metallic
            self.roughness = roughness
            self.isUnlit = isUnlit
            self.texture = texture
            self.shader = shader
        }

        private static func finite(_ value: SIMD4<Float>) -> Bool {
            value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
        }

        private static func finite(_ value: SIMD3<Float>) -> Bool {
            value.x.isFinite && value.y.isFinite && value.z.isFinite
        }
    }

    /// One uploaded mesh, material, and model transformation in a scene.
    public struct P5MeshInstance3D: @unchecked Sendable {
        /// Uploaded geometry.
        public let mesh: P5MetalMesh
        /// Surface values and shader.
        public let material: P5Material3D
        /// Model-to-world transform.
        public let modelMatrix: P5Matrix4x4

        /// Creates one renderable mesh instance.
        public init(
            mesh: P5MetalMesh,
            material: P5Material3D,
            modelMatrix: P5Matrix4x4 = .identity
        ) {
            self.mesh = mesh
            self.material = material
            self.modelMatrix = modelMatrix
        }
    }

    /// Immutable camera, lights, and mesh instances submitted as one render pass.
    public struct P5Scene3D: @unchecked Sendable {
        /// Active camera.
        public let camera: P5Camera3D
        /// Lights evaluated by the default shader.
        public let lights: [P5Light3D]
        /// Mesh instances in stable draw order.
        public let instances: [P5MeshInstance3D]

        /// Creates a scene snapshot.
        public init(
            camera: P5Camera3D,
            lights: [P5Light3D] = [.ambient(color: SIMD3(repeating: 1), intensity: 1)],
            instances: [P5MeshInstance3D] = []
        ) {
            self.camera = camera
            self.lights = lights
            self.instances = instances
        }
    }
#endif
