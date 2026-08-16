# Raster color, orientation, and export

Understand the explicit native raster contract before moving pixels between APIs.

## Color and alpha contract

`P5` uses logical top-left-origin canvas coordinates while Core Graphics keeps
its native image storage immutable. ``P5Image`` preserves the decoded
`CGImage` and its embedded color space until an operation requests a new
bitmap. Offscreen graphics, resizing, masking, software filters, frame capture,
and editable pixels render into 8-bit sRGB destinations.

``P5PixelBuffer`` exposes straight-alpha RGBA8 bytes. Conversion to Core
Graphics premultiplies RGB by alpha; conversion back safely unpremultiplies
partially transparent pixels and normalizes fully transparent pixels to clear
black. This prevents invisible RGB data from producing fringes during native
compositing.

Display P3 ``P5Color`` values remain wide-gamut while Core Graphics draws them
into a compatible destination. An sRGB offscreen or export destination performs
native color conversion. Extended-range/HDR component storage is outside the
1.0 raster contract: editable pixels and generated frames are SDR and clamp to
RGBA8. Decoded HDR images may retain their source `CGImage`, but processing them
creates SDR output.

## Orientation

ImageIO orientation metadata is applied when ImageIO creates the `CGImage`.
Drawing, cropping, pixels, masks, and snapshots then use normalized top-left
coordinates. The package does not retain or re-emit EXIF orientation tags after
processing; encoded output contains already oriented pixels.

Half-point stroke alignment follows Core Graphics: a one-point horizontal
stroke at `y = 0.5` covers the first raster row on a density-one flipped canvas.
Use ``P5Sketch/pixelDensity(_:)`` or an explicit offscreen density when aligning
to higher-density rasters.

## Still images and animations

``P5Image/encoded(as:quality:)`` and ``P5Image/write(to:format:quality:)`` use
ImageIO for PNG, JPEG, and HEIF. JPEG discards alpha according to ImageIO's
native encoder behavior. PNG preserves alpha.

``P5Sketch/captureFrame(pixelDensity:)`` renders queued operations into a new
bitmap without consuming them, so the native view can still present the same
frame. ``P5FrameSequence`` validates frame geometry and exports deterministic
animated GIF timing and loop metadata.

```swift
let first = try captureFrame(pixelDensity: 2)
let animation = P5FrameSequence(
    frames: [first, second, third],
    framesPerSecond: 24
)
try animation.writeGIF(to: outputURL)
```
