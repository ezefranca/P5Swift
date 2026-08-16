# Pointer Input

Handle mouse, touch, trackpad, and Apple Pencil input through one native event
model.

## Override a callback

Pointer callbacks execute synchronously on the main actor and receive a
``P5PointerEvent`` in top-left-origin canvas coordinates. Override only the
phases a sketch needs:

```swift
@MainActor
final class AttractorSketch: P5Sketch {
    private var attractor = CGPoint.zero

    override func pointerMoved(_ event: P5PointerEvent) {
        attractor = event.location
    }

    override func pointerDragged(_ event: P5PointerEvent) {
        attractor = event.location
    }

    override func pointerPressed(_ event: P5PointerEvent) {
        if event.button == .primary {
            attractor = event.location
        }
    }
}
```

The available callbacks are entry, exit, movement, dragging, press, release,
click, and cancellation. They are delivered in native event order. A release is
delivered before its corresponding click.

## Read persistent state

``P5Sketch/pointerPosition``, ``P5Sketch/previousPointerPosition``, and
``P5Sketch/pointerDelta`` retain the latest coordinates between callbacks and
frames. ``P5Sketch/pressedPointerButtons`` represents the complete held-button
set. ``P5Sketch/isPointerInside`` tracks mouse entry and exit, and
``P5Sketch/latestPointerEvent`` exposes device kind, normalized pressure,
modifiers, and monotonic timestamp when those values are needed in `draw()`.

Cancellation clears held-button state before calling
``P5Sketch/pointerCancelled(_:)``. This prevents interrupted touch sequences
from leaving a sketch in a permanently pressed state.

## Platform mapping

On macOS, an AppKit tracking area supplies mouse entry, exit, movement, every
button, click count, pressure, and modifiers. On iOS, UIKit supplies direct
touch, indirect pointer, and Apple Pencil input. Each active UIKit touch receives
a stable nonzero identifier; mouse events use identifier zero.

The shared ``P5PointerEvent`` deliberately contains no `NSEvent`, `UITouch`, or
`UIEvent` references. Events are value semantic, `Sendable`, and `Codable`, so a
test or replay system can record them and inject the same ordered sequence
without retaining platform objects. Decoding rejects nonfinite coordinates,
timestamps, and pressure.
