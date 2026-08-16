# Coordinates, Color, Concurrency, and Compatibility

Port p5.js ideas while preserving native Apple behavior.

## Compatibility map

| p5.js area | P5 equivalent | Intentional native difference |
| --- | --- | --- |
| `setup`, `draw`, loop control | ``P5Sketch`` lifecycle | Main-actor isolated and driven by native display callbacks. |
| Canvas 2D | ``P5Sketch`` drawing API | Core Graphics backs rendering; the public coordinate origin remains top-left. |
| `p5.Vector`, random, noise | ``P5Vector`` and sketch math state | Value semantics and explicit deterministic generators are available. |
| Color and pixels | ``P5Color``, ``P5PixelBuffer`` | Color space, alpha, orientation, and pixel density are explicit. |
| WebGL | ``P5MetalRenderer`` | Metal shaders are not GLSL source-compatible; submission is asynchronous. |
| DOM controls | ``P5Button``, ``P5Slider``, and native controls | SwiftUI/UIKit/AppKit replace HTML and CSS. |
| `load*` and storage | ``P5DataLoader``, ``P5Preferences``, ``P5FileStore`` | Loading and file work use `async`/`await`, typed failures, and cancellation. |
| Camera, sound, video | P5 AVFoundation adapters | Permission and lifecycle states are explicit. |

Authoritative behavior references live in the
[p5.js reference](https://p5js.org/reference/). P5 follows the reference where
the browser-independent meaning maps cleanly. It does not emulate JavaScript
coercion, global browser objects, CSS, Web Audio nodes, or WebGL shader source.

## Coordinates and transforms

The 2D API presents the p5.js top-left origin and increasing-y-down convention,
even where a native backing context is flipped. ``P5Transform`` values and
``P5Sketch/push()``/``P5Sketch/pop()`` make transform ownership explicit.
Image, rectangle, ellipse, and angle modes are sketch state and are restored by
the drawing-state stack.

P5 3D uses a right-handed world, a camera looking down negative z, and Metal's
`0...1` normalized depth. This is a deliberate Metal convention rather than a
WebGL matrix-byte compatibility promise.

## Color and raster data

``P5Color`` is a value. RGB, HSB, grayscale, alpha, hexadecimal, and Display P3
construction validate finite components against the sketch's configured ranges.
Raster APIs document whether alpha is straight or premultiplied at each native
boundary. Pixel buffers use top-left RGBA ordering; images retain orientation and
color-space decisions rather than relying on browser decoding defaults.

## Concurrency and ownership

Sketch lifecycle and view interaction stay on the main actor. File, network,
media, and Photos operations use structured concurrency and check cancellation.
``P5MetalRenderer`` is an actor; uploaded mesh, texture, shader, and target
wrappers are immutable references to native resources. Retain resources for the
duration of a scene and discard the renderer after a terminal Metal failure.

All platform-dependent work exposes an availability or authorization query plus
typed errors. P5 does not silently substitute a behavior whose timing, fidelity,
privacy, or performance semantics differ.
