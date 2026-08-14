# SwiftUI and Swift Playgrounds

Display a sketch in SwiftUI or run it interactively in Swift Playgrounds.

## Present a sketch in SwiftUI

Use ``P5SketchView`` to bridge a sketch into SwiftUI. The wrapper owns the
sketch for as long as SwiftUI presents it.

```swift
import CoreGraphics
import P5
import SwiftUI

@MainActor
final class OrbitSketch: P5Sketch {
    private var angle: CGFloat = 0

    override func setup() {
        frameRate(60)
        noStroke()
        fill(CGColor(red: 1, green: 0.2, blue: 0.5, alpha: 1))
    }

    override func draw() {
        background(CGColor(gray: 0.08, alpha: 1))

        let radius: CGFloat = 80
        let x = width / 2 + cos(angle) * radius
        let y = height / 2 + sin(angle) * radius
        circle(x, y, 32)
        angle += 0.03
    }
}

struct ContentView: View {
    private let canvasSize = CGSize(width: 600, height: 400)

    var body: some View {
        P5SketchView(size: canvasSize, makeSketch: OrbitSketch.init(size:))
            .accessibilityLabel("A pink circle orbiting on a dark canvas")
    }
}
```

``P5Sketch`` uses a fixed canvas size. When the `size` passed to
``P5SketchView`` changes, the wrapper creates a new sketch with the new
dimensions.

## Use a flexible SwiftUI layout

Read the available size with `GeometryReader` and pass it to the wrapper:

```swift
struct FlexibleSketchView: View {
    var body: some View {
        GeometryReader { proxy in
            P5SketchView(
                size: proxy.size,
                makeSketch: OrbitSketch.init(size:)
            )
        }
        .accessibilityLabel("An animated orbit")
    }
}
```

Keep mutable animation state inside your ``P5Sketch`` subclass rather than in
the SwiftUI view.

## Run in a Swift Playgrounds app

Create an **App** project in Swift Playgrounds, add this repository as a Swift
package dependency, and use the same SwiftUI view:

```swift
import P5
import SwiftUI

@main
struct P5PlaygroundApp: App {
    var body: some Scene {
        WindowGroup {
            P5SketchView(
                size: CGSize(width: 600, height: 400),
                makeSketch: OrbitSketch.init(size:)
            )
            .accessibilityLabel("An animated orbit")
        }
    }
}
```

When adding the package, select version `0.3.0` or later.

## Run in an Xcode playground

For an iOS playground, host the SwiftUI view as the live view:

```swift
import P5
import PlaygroundSupport
import SwiftUI
import UIKit

PlaygroundPage.current.needsIndefiniteExecution = true

Task { @MainActor in
    let content = P5SketchView(
        size: CGSize(width: 600, height: 400),
        makeSketch: OrbitSketch.init(size:)
    )

    PlaygroundPage.current.setLiveView(
        UIHostingController(rootView: content)
    )
}
```

The indefinite execution setting keeps the playground alive so the sketch can
continue drawing frames.
