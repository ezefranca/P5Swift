import CoreGraphics

@MainActor
protocol P5SketchInternal {
    var isLooping: Bool { get set }
    var framesPerSecond: Double { get set }
    var userWantsRedraw: Bool { get set }
    var pixelDensity: CGFloat { get set }

    func addOperation(_ operation: P5Operation)
    func resize(to size: CGSize)
    func canvasMetrics() -> P5CanvasMetrics
}
