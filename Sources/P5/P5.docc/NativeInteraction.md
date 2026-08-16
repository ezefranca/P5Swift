# Native interaction

Handle focus, hover, scrolling, drag and drop, clipboard access, and semantic
accessibility actions without retaining AppKit or UIKit event objects.

## Focus and hover

``P5Sketch/isFocused`` and ``P5Sketch/isHovered`` are updated before their
callbacks run. Request native keyboard focus with ``P5Sketch/requestFocus()``
and override only the transitions the sketch needs:

```swift
override func focusGained(_ event: P5FocusEvent) {
    stroke(.white)
}

override func hoverMoved(_ event: P5HoverEvent) {
    cursor = event.location
}
```

``P5Sketch/focusChanged(_:)`` and ``P5Sketch/hoverChanged(_:)`` observe every
transition. The phase-specific focus and hover callbacks run immediately after
their general callback. Mouse and indirect-pointer entry, movement, and exit
produce hover values automatically. Direct touch does not imply hover.

Native first-responder transitions use ``P5FocusCause/system``. Hosts that can
distinguish pointer, keyboard-navigation, or programmatic focus may preserve
that cause by calling ``P5Sketch/injectFocusEvent(_:)``.

## Precision scrolling

Override ``P5Sketch/scrolled(_:)`` to receive a ``P5ScrollEvent``. Its delta,
location, modifiers, precision, direction-inversion, momentum, phase, and
monotonic timestamp are portable values. AppKit wheel and trackpad events are
bridged automatically. A SwiftUI or UIKit host can normalize another scrolling
source and deliver it through ``P5Sketch/injectScrollEvent(_:)``.

```swift
override func scrolled(_ event: P5ScrollEvent) {
    zoom = max(0.1, zoom + event.delta.dy * 0.01)
}
```

The delta retains the native device direction. Inspect
``P5ScrollEvent/isDirectionInverted`` when physical wheel direction matters.

## Drag and drop

Drop providers often load asynchronously and their file-access lifetime belongs
to the containing application. Resolve a SwiftUI `Transferable`, UIKit item
provider, or AppKit pasteboard in the host, then inject an ordered
``P5DropEvent`` containing ``P5DropPayload/file(_:)``,
``P5DropPayload/text(_:)``, or
``P5DropPayload/data(_:typeIdentifier:)`` values.

```swift
sketch.injectDropEvent(
    P5DropEvent(
        phase: .performed,
        location: dropLocation,
        payloads: [.file(importedURL)],
        timestamp: ProcessInfo.processInfo.systemUptime
    )
)
```

Keep any security-scoped file access open for as long as the sketch uses that
URL. p5.swift never extends access or silently copies a dropped file.

## Clipboard privacy

``P5Clipboard/general`` provides main-actor access to native plain text and
Uniform Type Identifier data. Clipboard calls are explicit and synchronous:

```swift
P5Clipboard.general.setText("Copied from the sketch")
let text = P5Clipboard.general.text
```

Read the clipboard only after a user action. Apple platforms can notify users
or require confirmation when an application reads data written by another
application. p5.swift does not poll the clipboard or cache its contents.

## Accessible canvases and actions

Set ``P5Sketch/accessibilityLabel``, ``P5Sketch/accessibilityValue``, and
``P5Sketch/accessibilityHint`` to expose the native canvas as one semantic
element. Override ``P5Sketch/accessibilityAction(_:)`` and return `true` for
handled actions:

```swift
override func accessibilityAction(_ event: P5AccessibilityEvent) -> Bool {
    switch event.action {
    case .activate:
        resetSimulation()
        return true
    case .increment:
        particleCount += 1
        return true
    default:
        return false
    }
}
```

VoiceOver activation, increment, decrement, and escape actions bridge through
this callback on AppKit and UIKit. Hosts can inject named
``P5AccessibilityAction/custom(_:)`` actions. Returning `false` lets the native
view continue its default accessibility handling.

## Ordering and replay

All state mutation and callbacks run synchronously on the main actor. The
latest-event properties are updated before callbacks, and a phase-specific
callback follows its general callback. Every interaction event is `Sendable`,
`Hashable`, and `Codable`; decoding revalidates finite coordinates and
nonnegative monotonic timestamps. Tests, automation, and replay tools therefore
use the same injection methods as host adapters without platform event objects.
