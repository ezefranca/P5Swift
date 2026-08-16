# Metal 3D Rendering

Upload validated meshes and images once, compose immutable scene snapshots, and
submit explicit Metal render passes without changing P5's Core Graphics 2D path.

## Overview

``P5MetalRenderer`` is an actor that owns one `MTLDevice`, command queue,
fallback texture, default shader, pipeline cache, and depth-state cache. It is a
separate renderer rather than a mode on ``P5Sketch``: existing 2D sketches keep
using Core Graphics, while applications that opt into 3D create and schedule
their Metal work explicitly.

Metal is required. Construction throws ``P5Metal3DError/unavailable`` when no
device exists, and the renderer never silently moves a failed GPU operation to
the CPU. Use ``P5MetalRenderer/isAvailable`` for a capability check and surface
the typed construction or submission error when 3D is unavailable.

```swift
guard P5MetalRenderer.isAvailable else {
    // Present a platform-appropriate unsupported-device message.
    return
}

let renderer = try P5MetalRenderer()
let mesh = try await renderer.makeMesh(.sphere())
let material = try P5Material3D(
    baseColor: SIMD4(0.2, 0.7, 1, 1),
    metallic: 0.1,
    roughness: 0.45
)
let camera = try P5Camera3D()
let scene = P5Scene3D(
    camera: camera,
    lights: [
        .ambient(color: SIMD3(repeating: 1), intensity: 0.2),
        .directional(
            direction: P5Vector(x: -1, y: -1, z: -1),
            color: SIMD3(repeating: 1),
            intensity: 0.9
        ),
    ],
    instances: [P5MeshInstance3D(mesh: mesh, material: material)]
)
let target = try await renderer.makeRenderTarget(width: 1_024, height: 1_024)
let statistics = try await renderer.render(scene, to: target)
```

The public resource wrappers are immutable and `@unchecked Sendable` because
Metal declares its resource protocols outside Swift's checked concurrency
model. A renderer actor serializes creation and submission. Keep wrappers alive
for as long as a scene refers to them, and do not mutate a wrapped application
texture while a render operation is using it.

## Coordinates and cameras

P5 3D uses a right-handed world. A default camera sits at positive z and looks
toward the origin; visible points are in its negative-z direction. Projection
matrices produce Metal's normalized depth interval of `0...1`. Meshes use
counterclockwise front faces by default. See <doc:Metal3DGeometry> for matrix,
camera, primitive, normal, and OBJ conventions.

Each ``P5MeshInstance3D`` combines an uploaded ``P5MetalMesh``, a validated
``P5Material3D``, and a model matrix. A model matrix whose upper-left 3-by-3
portion has no finite inverse is rejected before command encoding, because a
normal matrix cannot be derived from it.

## Materials, textures, and lights

The bundled shader multiplies vertex color, material base color, and an optional
sampled texture. Unlit materials add their emissive color and skip lighting.
Lit materials support as many as ``P5MetalRenderer/maximumLightCount`` ambient,
directional, and finite-range point lights. Components must be finite; colors
and intensities cannot be negative, and point-light ranges must be positive.

``P5MetalRenderer/makeTexture(from:configuration:)`` copies a ``P5Image`` into
a Metal shader-read texture and creates a matching immutable sampler.
``P5TextureConfiguration3D`` selects nearest or linear filtering, clamping or
repetition, and mipmap generation. P5 images are straight-alpha RGBA values at
the API boundary. Image creation performs the documented Core Graphics
premultiplication, while Metal texture loading and shader sampling use the
texture's native representation. The default loader treats color components as
linear rather than implicitly applying sRGB conversion.

## Render passes and targets

``P5RenderConfiguration3D`` validates color format, clear color, and sample
count before submission. It controls:

- read/write, read-only, or disabled depth testing;
- optional front-and-back stencil operations and masks;
- front- or back-face culling and front-face winding;
- opaque, source-alpha, or additive blending;
- one-, two-, four-, or eight-sample rendering.

The selected device is checked separately for sample-count support. For MSAA,
the renderer allocates a private multisample color texture and resolves it into
the single-sample target. Depth and stencil attachments are private,
pass-scoped resources. Allocation failures are reported distinctly as
``P5Metal3DError/multisampleCreationFailed`` or
``P5Metal3DError/depthStencilCreationFailed``.

Use ``P5MetalRenderer/makeRenderTarget(width:height:colorFormat:)`` for a shared
offscreen target. A compatible application-owned `MTLTexture` can instead be
wrapped with ``P5MetalRenderTarget/init(texture:)``. It must be a nonempty,
single-sample, two-dimensional render-target texture in one of the formats in
``P5PixelFormat3D``. The target's format and the render configuration must
match.

BGRA8 shared targets support ``P5MetalRenderTarget/pixelBuffer(pixelDensity:)``
after rendering completes. The method returns top-left, straight-alpha RGBA8
bytes. Floating-point and private targets deliberately reject CPU readback.

## MetalKit presentation

``P5MetalViewConfiguration`` applies a validated refresh rate, on-demand or
continuous drawing, color format, and drawable policy to an `MTKView` on the
main actor. Ask it for the current ``P5MetalRenderTarget`` inside the view's draw
cycle; a missing drawable is normal while the view is hidden, detached, or
temporarily unable to present.

```swift
@MainActor
func draw(in view: MTKView) async throws {
    let viewConfiguration = try P5MetalViewConfiguration()
    guard let target = try viewConfiguration.renderTarget(from: view) else {
        return
    }
    try await renderer.render(scene, to: target)
}
```

The renderer presents a wrapped drawable on its command buffer and awaits GPU
completion before returning. ``P5MetalRendererStatistics`` distinguishes
submitted and completed frames and records the last draw count, triangle count,
and Metal-reported GPU interval when the device supplies one.

## Custom shaders

``P5MetalRenderer/makeShader(source:vertexFunction:fragmentFunction:)`` compiles
source for the renderer's device. A compatible vertex function receives:

- buffer 0: an array of vertices containing aligned `float3 position`, aligned
  `float3 normal`, `float2 textureCoordinate`, and `float4 color` fields;
- buffer 1: model and view-projection `float4x4` values, a `float3x3` normal
  matrix, followed by four `float4` material/camera parameter vectors.

A compatible fragment function receives the same uniforms at buffer 1, an
array of three-`float4` light records at buffer 2, the `uint` light count at
buffer 3, the material texture at texture 0, and its sampler at sampler 0. The
material-parameter vector contains metallic, roughness, has-texture, and
is-unlit values in that order. The emissive vector uses RGB and reserves alpha.
The bundled `P5Renderer3D.metal` resource is the executable ABI reference.

Compilation, missing entry points, and pipeline creation are separate typed
failures. A shader object is immutable and pipelines are cached by shader,
target format, sample count, blend mode, and depth/stencil presence.

## Cancellation and failures

Rendering checks cooperative cancellation before resource work, after command
encoding, and after GPU completion. Cancellation cannot retract work already
accepted by Metal, so callers must treat it as cancellation of their wait and
subsequent state update—not as proof that the GPU did no work. Actor isolation
keeps statistics and caches consistent across concurrent callers.

Handle ``P5Metal3DError`` at the capability boundary. It separates unavailable
hardware, shader and pipeline errors, allocation errors, incompatible targets,
invalid scenes, command creation/encoding failures, command execution failure,
and unavailable readback. `errorDescription` is suitable for diagnostics; an
application can map individual cases to localized user-facing recovery text.

No P5 API can guarantee recovery from device removal or a process-wide Metal
failure. Discard the renderer and its resources after a terminal command error,
then attempt to construct a fresh renderer only when that matches the
application's lifecycle and recovery policy.
