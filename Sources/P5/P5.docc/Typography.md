# Native typography

Load, measure, wrap, align, and draw text with Core Text.

## Overview

``P5Font`` owns immutable `CGFont` geometry and is safe to share across
concurrency domains. A font value does not freeze a point size; select size and
leading on each sketch.

```swift
let font = try P5Font.load(from: fontFileURL)

textFont(font)
textSize(24)
textLeading(30)
textAlign(.center, .top)
textWrap(.word)
text("Native creative coding", width / 2, 20, 240, 100)
```

``P5Font/system(named:)`` asks Core Text for the requested PostScript name. As
with Apple text APIs, an unavailable name resolves through Core Text's native
font fallback rather than producing a web-font loading error. File loading is
synchronous because callers already own a local URL; use an asynchronous file
or network layer before passing downloaded bytes to ``P5Font/decode(_:)``.

## Measure before drawing

``P5Sketch/textBounds(_:width:)`` uses the same font, size, leading, alignment,
and wrapping configuration as drawing.

```swift
let metrics = textBounds("one two three", width: 120)
let height = metrics.bounds.height
let firstBaseline = metrics.ascent
```

The returned ``P5TextMetrics`` reports Core Text ascent and descent, configured
baseline spacing, suggested top-left-origin bounds, and line count. Raster
drawing follows the canvas' current transform and color/blend state. A fill
draws glyph interiors, a stroke outlines them, and disabling both skips the
text operation.

## Coordinate behavior

Unconstrained text treats its `(x, y)` pair as an alignment anchor. The default
is left/baseline, matching p5.js. Constrained text treats the supplied values as
a top-left-origin layout rectangle. Vertical top, center, baseline, and bottom
alignment are calculated in canvas points before Core Text draws into its
native bottom-left local frame.
