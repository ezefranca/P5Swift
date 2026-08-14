import CoreGraphics
import SwiftUI

/// A SwiftUI view that owns and displays a ``P5Sketch``.
///
/// The view creates a sketch for the supplied size and keeps it alive while
/// SwiftUI presents the underlying native canvas. If `size` changes, the view
/// creates a new sketch because ``P5Sketch`` canvases have fixed dimensions.
///
/// ```swift
/// P5SketchView(size: CGSize(width: 400, height: 300)) { size in
///     MySketch(size: size)
/// }
/// ```
///
/// Apply an accessibility label that describes the rendered visualization:
///
/// ```swift
/// P5SketchView(size: size, makeSketch: MySketch.init(size:))
///     .accessibilityLabel("Animated particle field")
/// ```
@MainActor
public struct P5SketchView<Sketch: P5Sketch>: View {
    private let size: CGSize
    private let makeSketch: @MainActor (CGSize) -> Sketch

    /// Creates a SwiftUI view that displays a sketch.
    ///
    /// - Parameters:
    ///   - size: The canvas size in points.
    ///   - makeSketch: A closure that creates a sketch for the canvas size.
    public init(
        size: CGSize,
        makeSketch: @escaping @MainActor (CGSize) -> Sketch
    ) {
        self.size = size
        self.makeSketch = makeSketch
    }

    /// The SwiftUI content that hosts the native sketch canvas.
    public var body: some View {
        P5SketchPlatformView(size: size, makeSketch: makeSketch)
            .frame(width: size.width, height: size.height)
    }
}
