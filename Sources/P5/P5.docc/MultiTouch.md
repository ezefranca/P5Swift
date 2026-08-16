# Deterministic multi-touch

Track fingers, Apple Pencil, and indirect touches with stable native identifiers.

## Overview

``P5Sketch/touches`` contains active non-mouse pointers sorted by identifier.
Identifiers remain stable from press through release or cancellation and are
not reused during that active lifetime. Every state transition produces a
``P5TouchEvent`` after the corresponding pointer callback.

```swift
@MainActor
final class DrawingSketch: P5Sketch {
    override func touchesMoved(_ event: P5TouchEvent) {
        for touch in event.activeTouches {
            line(
                touch.previousLocation.x,
                touch.previousLocation.y,
                touch.location.x,
                touch.location.y
            )
        }
    }
}
```

``P5Touch`` and ``P5TouchEvent`` are `Sendable`, `Hashable`, and `Codable`, so
tests and tools can inject, record, and replay the same ordered values. Delivery
and callbacks run on the main actor. Active touches are updated before pointer
and touch callbacks; ended and cancelled touches are absent from the event's
``P5TouchEvent/activeTouches`` snapshot.

## Gesture recognizer coexistence

The canvas installs no UIKit gesture recognizers itself. Host recognizers retain
their native behavior by default. Select cooperative mode when existing host
recognizers should observe gestures without cancelling or delaying canvas
touches:

```swift
gestureCoexistence(.cooperative)
```

On UIKit, cooperative mode updates recognizers already attached to the canvas.
Recognizer delegates still decide whether two native recognizers may recognize
simultaneously. On AppKit, the mode is retained as portable configuration but
does not change mouse delivery.
