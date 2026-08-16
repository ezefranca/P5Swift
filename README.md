# p5.swift

<p align="center"><img src="Assets/P5.svg" width="112" alt="P5 icon"></p>

> [!IMPORTANT]
> p5.swift is an expanded fork of [Juan Hurtado's P5Swift](https://github.com/juandahurt/P5Swift). The original project established the Core Graphics sketch model this package develops.

[![Tests](https://github.com/ezefranca/p5.swift/actions/workflows/tests.yml/badge.svg)](https://github.com/ezefranca/p5.swift/actions/workflows/tests.yml)
[![Documentation](https://github.com/ezefranca/p5.swift/actions/workflows/documentation.yml/badge.svg)](https://ezefranca.com/p5.swift/documentation/p5/)
[![Swift Package Index](https://img.shields.io/badge/Swift_Package_Index-ready-0D96F6?logo=swift)](https://swiftpackageindex.com/ezefranca/p5.swift)
[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)](Scripts/check_coverage.py)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%2B%20%7C%20macOS%2014%2B-black?logo=apple)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

p5.swift brings the lifecycle and creative-coding vocabulary of [p5.js](https://p5js.org/) to native Swift. It combines Core Graphics 2D drawing, Metal 3D, SwiftUI/UIKit/AppKit presentation, deterministic math, native input, media, audio, persistence, export, and accessible controls in one independent Swift package.

The package is a pre-1.0 release candidate. Its public API, DocC inventory, 100% production line/region coverage gates, and macOS/iOS build matrix are enforced in CI.

## Add the package

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/ezefranca/p5.swift
```

For the release-candidate branch in another Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/ezefranca/p5.swift", branch: "main")
]
```

Add the `P5` product to the application target and `import P5`.

## Create a sketch

```swift
import P5

@MainActor
final class OrbitSketch: P5Sketch {
    private var angle: CGFloat = 0

    override func setup() {
        frameRate(60)
        noStroke()
        fill(51, 181, 229)
    }

    override func draw() {
        background(18)
        circle(
            width / 2 + cos(angle) * 80,
            height / 2 + sin(angle) * 80,
            32
        )
        angle += 0.03
    }
}
```

Present it with `P5SketchView` in SwiftUI or retain the sketch and embed its native `view` in UIKit/AppKit. See [Your First P5 Sketch](Sources/P5/P5.docc/GettingStarted.md) and the [complete DocC site](https://ezefranca.com/p5.swift/documentation/p5/).

## Capability map

| Area | Native implementation |
| --- | --- |
| 2D drawing, text, images, pixels | Core Graphics, Core Text, Core Image, ImageIO |
| 3D scenes, meshes, lights, textures | Actor-owned Metal renderer and MetalKit presentation |
| Lifecycle and UI | Main-actor sketches with SwiftUI, UIKit, and AppKit |
| Input and accessibility | Pointer, Pencil, touch, keyboard, drag/drop, clipboard, VoiceOver actions |
| Camera, video, audio, Photos | Permission-aware AVFoundation and Photos adapters |
| Data, persistence, export | URLSession, typed tables, UserDefaults/files, PNG/JPEG/HEIF/GIF/video |
| Math | Vectors, transforms, seeded randomness, Gaussian sampling, Perlin noise |

Browser globals, HTML/CSS, JavaScript coercion, Web Audio graphs, and GLSL are intentionally mapped to native Apple concepts rather than emulated. The [compatibility guide](Sources/P5/P5.docc/P5CompatibilityAndConcepts.md) records those differences.

## Run and validate

```sh
swift run P5SmokeSample
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/validate.sh
```

The complete validator runs policy, privacy, dependency, workflow, link, formatting, Release, test/coverage, symbol documentation, API-digester, DocC, macOS/iOS test-plan, and Debug/Release application gates. See [Contributing](CONTRIBUTING.md) and [Releasing](Documentation/Releasing.md).

## Package family

- [matter.swift](https://github.com/ezefranca/matter.swift) — deterministic native physics inspired by Matter.js.
- [ml5.swift](https://github.com/ezefranca/ml5.swift) — approachable Core ML and native dense training inspired by ml5.js.

The repositories are independently versioned and have no production dependency on one another. Applications may compose any combination.

## Scope and attribution

The reusable API requirements were audited against Daniel Shiffman's [The Nature of Code](https://natureofcode.com/), but exhaustive example ports are intentionally outside the package. See [Nature of Code compatibility](Sources/P5/P5.docc/NatureOfCodeCompatibility.md) and [third-party notices](THIRD_PARTY_NOTICES.md).
