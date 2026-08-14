import CoreGraphics

@MainActor
final class P5SketchViewCoordinator<Sketch: P5Sketch> {
    private(set) var size: CGSize
    private(set) var sketch: Sketch

    init(
        size: CGSize,
        makeSketch: @MainActor (CGSize) -> Sketch
    ) {
        self.size = size
        sketch = makeSketch(size)
    }

    func replaceSketch(
        for size: CGSize,
        using makeSketch: @MainActor (CGSize) -> Sketch
    ) {
        sketch.view.removeFromSuperview()
        self.size = size
        sketch = makeSketch(size)
    }
}
