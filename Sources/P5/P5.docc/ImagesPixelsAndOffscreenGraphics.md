# Images, pixels, and offscreen graphics

Load and export images through Apple frameworks while keeping raster ownership explicit.

## Overview

``P5Image`` wraps an immutable `CGImage` and records how many raster pixels
represent one logical canvas point. It is safe to pass across concurrency
domains because Core Graphics image storage is immutable. Decode existing
bytes with ``P5Image/decode(_:pixelDensity:)``, resolve a bundle resource with
``P5Image/loadResource(named:withExtension:in:pixelDensity:)``, or use
``P5Image/load(from:pixelDensity:session:)`` for cancellable file and network
loading.

```swift
let icon = try P5Image.loadResource(
    named: "Particle",
    withExtension: "png",
    in: .main,
    pixelDensity: 2
)

let remote = try await P5Image.load(from: imageURL)
```

Network loading uses the supplied `URLSession`; non-successful HTTP responses
produce ``P5ImageError/invalidHTTPStatus(_:)``. The package does not cache or
persist downloaded images implicitly.

## Draw and tint images

Image destinations use top-left-origin canvas points. Select `.corner`,
`.corners`, or `.center` with ``P5Sketch/imageMode(_:)``. Cropped drawing also
uses logical source points rather than raw pixels.

```swift
imageMode(.center)
tint(P5Color(red: 1, green: 0.5, blue: 0.5))
image(remote, width / 2, height / 2, 160, 90)
noTint()
```

Tint is implemented with native Core Graphics compositing and preserves the
source alpha mask. ``P5Sketch/clear()`` removes pixels to transparent black;
``P5Sketch/background(_:)`` paints the full canvas independently of the current
user transform.

## Edit RGBA pixels

``P5PixelBuffer`` stores straight-alpha RGBA8 bytes in top-left, row-major
order. `P5Image` converts to and from Core Graphics' premultiplied-alpha native
storage at the boundary.

```swift
var pixels = try image.pixelBuffer()
pixels.setColor(.init(red: 1, green: 0, blue: 0), x: 10, y: 10)
let edited = try P5Image(pixelBuffer: pixels)
```

Coordinates passed to pixel methods are raster coordinates. Use
``P5PixelBuffer/pixelDensity`` and ``P5PixelBuffer/size`` when mapping between
raster pixels and logical points.

## Render offscreen

``P5Graphics`` inherits the two-dimensional `P5Sketch` drawing vocabulary and
retains pixels between snapshots.

```swift
let layer = try createGraphics(320, 180, pixelDensity: 2)
layer.clear()
layer.noStroke()
layer.fill(P5Color(red: 0.2, green: 0.5, blue: 1))
layer.circle(160, 90, 80)

let frame = try layer.snapshot()
try frame.write(to: outputURL, format: .png)
```

Queued commands flush when a snapshot or pixel load is requested. Style and
pixels persist, while the transformation matrix starts at identity after each
flush. This explicit boundary keeps offscreen resource lifetime deterministic.
