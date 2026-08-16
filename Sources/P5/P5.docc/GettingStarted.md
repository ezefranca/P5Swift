# Your First P5 Sketch

Create a native, accessible creative-coding canvas and understand its ownership.

## Build a sketch

Add the `P5` product to an iOS or macOS target, import `P5`, and subclass
``P5Sketch`` on the main actor:

```swift
import P5

@MainActor
final class PulseSketch: P5Sketch {
    override func setup() {
        frameRate(60)
        noStroke()
    }

    override func draw() {
        background(24)
        let diameter = 40 + 20 * sin(Double(frameCount) * 0.05)
        fill(51, 181, 229)
        circle(width / 2, height / 2, diameter)
    }
}
```

Present it from SwiftUI with ``P5SketchView`` and describe the changing visual
for VoiceOver. Respect Reduce Motion in application state by calling
``P5Sketch/noLoop()`` or by drawing a static equivalent.

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        P5SketchView(size: CGSize(width: 480, height: 320), makeSketch: PulseSketch.init)
            .accessibilityLabel("A blue circle gently changing size")
    }
}
```

The view owns the native canvas; the sketch owns its drawing state and frame
driver. UIKit and AppKit hosts must keep a strong reference to the sketch while
embedding ``P5Sketch/view``.

## Handle a capability boundary

The Core Graphics path works on every supported platform. Metal 3D, camera,
microphone, Photos, and file operations are explicit capabilities and can fail.
Check availability before creating a renderer and preserve the typed error for
diagnostics:

```swift
guard P5MetalRenderer.isAvailable else {
    // Show a localized 2D-only message.
    return
}

do {
    let renderer = try P5MetalRenderer()
    // Upload immutable resources, then submit scenes through the renderer actor.
    _ = renderer
} catch let error as P5Metal3DError {
    // Map the typed case to an application-specific recovery action.
    print(error.localizedDescription)
}
```

## Next steps

- Learn deterministic animation in <doc:TimingAndDeterminism>.
- Learn coordinates, color, and native differences in
  <doc:P5CompatibilityAndConcepts>.
- Build GPU scenes with <doc:Metal3DRendering>.
- Port browser-style controls with <doc:NativeControls>.
