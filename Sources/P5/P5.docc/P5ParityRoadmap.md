# P5 Parity Roadmap

Grow p5.swift into a near-complete native port of p5.js creative-coding
capabilities.

## The compatibility goal

p5.swift aims for conceptual and behavioral parity rather than a mechanical
translation of JavaScript. Familiar p5.js sketches should be straightforward
to port while still using Swift types, compile-time safety, the main actor,
and native Apple frameworks.

The project can cover substantially more than its current drawing subset:

- The platform-independent p5.js 2D API can be implemented directly.
- Browser media capabilities can use AVFoundation.
- WebGL concepts can use a Metal renderer.
- Storage, networking, and file APIs can use Foundation and native pickers.
- DOM-oriented user interfaces can use SwiftUI, UIKit, or AppKit components.

Literal JavaScript and browser objects such as `window`, `document`, HTML
elements, and CSS rules have no direct native equivalent. p5.swift provides
native capability mappings instead of pretending those objects exist.

## Phase 1: Complete the 2D foundation

Establish the behavior required by most Coding Train and p5.js 2D sketches:

- Numeric and grayscale color overloads, alpha, and color modes.
- Points, triangles, quads, arcs, rounded rectangles, and shape modes.
- `beginShape()`, vertices, curves, Bézier paths, contours, and `endShape()`.
- Scale, shear, matrix operations, angle modes, line caps, and line joins.
- Text loading, measurement, alignment, wrapping, and drawing.
- Image loading, drawing, resizing, tinting, masking, and blend modes.
- Mouse, touch, keyboard, focus, timing, and canvas-resize events.

## Phase 2: Creative-coding utilities

Add the reusable APIs that make p5.js sketches concise:

- `P5Vector` and vector arithmetic.
- Random generation, deterministic seeds, Gaussian values, and noise.
- Mapping, interpolation, constraints, normalization, and trigonometry.
- Date, time, frame count, delta time, and device display information.
- Pixel access, filters, image sampling, and color interpolation.
- Offscreen graphics buffers and reusable drawing contexts.
- Image and animation export.

## Phase 3: Native media and audio

Map browser media features to Apple frameworks:

- Camera and microphone capture through AVFoundation.
- Video playback, frame extraction, and recording.
- Audio files, oscillators, amplitude analysis, and FFT data.
- Permission-aware APIs with explicit errors and lifecycle management.
- Photos and file importer/exporter integration.

These APIs will preserve p5.js terminology where it remains clear, but
authorization and asynchronous loading will follow Swift concurrency.

## Phase 4: Metal-backed 3D

Build a renderer that maps p5.js WebGL concepts onto Metal:

- 3D primitives, meshes, cameras, projections, materials, and lights.
- Texture loading and offscreen render targets.
- Shader APIs adapted for Metal Shading Language.
- Model loading and normal generation.
- Depth, stencil, blending, and antialiasing controls.

The goal is sketch portability and familiar behavior, not WebGL binary or
shader-source compatibility.

## Phase 5: Native interface integrations

Provide optional integrations rather than cloning the browser DOM:

- SwiftUI controls and observable sketch state.
- UIKit and AppKit event and view adapters.
- Accessibility descriptions and reduced-motion behavior.
- Drag and drop, clipboard, file dialogs, and sharing.
- URLSession networking and native persistence helpers.

## Compatibility policy

Each implemented API should:

1. Link to the corresponding p5.js reference.
2. Document intentional differences caused by Swift or Apple platforms.
3. Include behavioral tests for geometry, state, and error handling.
4. Prefer p5.js naming when it remains fluent and unambiguous in Swift.
5. Surface unsupported behavior explicitly rather than silently ignoring it.

The current implementation is the foundation, not the intended endpoint.
