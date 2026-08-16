# Keyboard Input

Use semantic keys and persistent held-key state without depending on AppKit or
UIKit event types.

## Handle key phases

Override the callbacks needed by a sketch. Press callbacks include native key
repeat, while typed callbacks contain printable text after modifier processing.

```swift
@MainActor
final class VehicleSketch: P5Sketch {
    override func keyPressed(_ event: P5KeyboardEvent) {
        if event.key == .space, !event.isRepeat {
            launchVehicle()
        }
    }

    override func keyTyped(_ event: P5KeyboardEvent) {
        if event.characters == "r" {
            resetSimulation()
        }
    }
}
```

``P5Sketch/keyPressed(_:)``, ``P5Sketch/keyReleased(_:)``,
``P5Sketch/keyTyped(_:)``, and ``P5Sketch/keyCancelled(_:)`` execute
synchronously on the main actor in native event order. Command and Control
shortcuts do not produce typed callbacks.

## Query held keys

``P5Sketch/pressedKeys`` is a set of semantic ``P5Key`` values.
``P5Sketch/isKeyPressed`` reports whether the set is nonempty, and
``P5Sketch/keyIsDown(_:)`` checks an individual key. A release or cancellation
removes its key before the corresponding callback. ``P5Sketch/latestKeyboardEvent``
retains the last phase, modifiers, repeat state, native hardware code, produced
text, and monotonic timestamp.

```swift
override func draw() {
    if keyIsDown(.arrowLeft) { velocity.x -= 0.2 }
    if keyIsDown(.arrowRight) { velocity.x += 0.2 }
}
```

## Platform mapping and replay

AppKit hardware codes and UIKit HID usages map to semantic navigation, editing,
modifier, space, and function keys. Unknown codes remain available as
``P5Key/unidentified(_:)``. Clicking or touching the canvas makes its native
view the first responder.

``P5KeyboardEvent`` is value semantic, `Sendable`, and `Codable`. Its decoder
rejects empty text, invalid numbered function keys, typed phases without text,
and nonfinite timestamps. Tests and replay tools can therefore inject recorded
events through the same ordered state transition used by native input.
