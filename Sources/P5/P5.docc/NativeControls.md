# Native Controls

Build a sketch interface from Apple-native controls instead of reproducing the
browser DOM.

## Overview

p5.js examples often create HTML buttons, sliders, inputs, paragraphs, checkboxes,
select menus, and color inputs. p5.swift maps those roles to SwiftUI first:

| p5.js role | p5.swift | Apple control |
| --- | --- | --- |
| Button | ``P5Button`` | `SwiftUI.Button` |
| Range input | ``P5Slider`` | `SwiftUI.Slider` |
| Text input | ``P5TextField`` | `SwiftUI.TextField` |
| Text or paragraph | ``P5Label`` | `SwiftUI.Text` |
| Checkbox | ``P5Toggle`` | `SwiftUI.Toggle` |
| Select menu | ``P5Picker`` | `SwiftUI.Picker` |
| Color input | ``P5ColorPicker`` | `SwiftUI.ColorPicker` |

The wrappers preserve standard platform styling, keyboard behavior, focus,
localization, Dynamic Type, VoiceOver semantics, and pointer behavior. Apply normal
SwiftUI modifiers when a sketch needs a custom layout or appearance.

## Share observable state

``P5ControlState`` is a small Observation-backed main-actor reference. Its binding can
drive a control while the sketch reads the same value:

```swift
@MainActor
final class ParticleControls {
    let speed = P5ControlState(0.5)
    let trails = P5ControlState(true)
}

struct ControlsView: View {
    let controls: ParticleControls

    var body: some View {
        Form {
            P5Slider(
                value: controls.speed.binding,
                in: 0...2,
                step: 0.05,
                label: "Speed"
            )
            P5Toggle("Draw trails", isOn: controls.trails.binding)
        }
    }
}
```

Keep UI mutation on the main actor. A background simulation can publish a Sendable
snapshot and explicitly hop to `MainActor` before updating control state.

## Selection and input

Picker options use ``P5ControlOption`` so selection identity is stable and independent
of localized display text:

```swift
enum MotionMode: Hashable, Sendable {
    case flow
    case orbit
}

let mode = P5ControlState(MotionMode.flow)

P5Picker(
    "Motion",
    selection: mode.binding,
    options: [
        P5ControlOption("Flow field", value: .flow),
        P5ControlOption("Orbit", value: .orbit),
    ]
)
```

Picker options must be nonempty and unique, and the initial selection must exist in
the list. Slider bounds must be finite and increasing; optional steps must be positive
and finite.

## Embed AppKit or UIKit controls

Use ``P5NativeControlFactory`` when a host application lays out views directly rather
than through SwiftUI. It returns actual `NSButton`, `NSSlider`, `NSTextField`, and
related AppKit controls on macOS, and the corresponding UIKit controls on iOS.

```swift
let slider = P5NativeControlFactory.slider(
    value: 0.5,
    in: 0...1,
    accessibilityLabel: "Particle speed"
) { newValue in
    sketchSpeed = newValue
}
```

Factory-created controls retain their callbacks for their own lifetime. AppKit and
UIKit text-field callbacks use the native commit event; use a delegate or SwiftUI
binding when every editing change must be observed. The factory assigns useful
default accessibility labels, while allowing the host to provide a more descriptive
label.

## Topics

### Shared state

- ``P5ControlState``
- ``P5ControlOption``

### SwiftUI controls

- ``P5Button``
- ``P5Slider``
- ``P5TextField``
- ``P5Label``
- ``P5Toggle``
- ``P5Picker``
- ``P5ColorPicker``

### Platform views

- ``P5NativeControlFactory``
