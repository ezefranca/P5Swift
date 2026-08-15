import CoreGraphics

/// A native drawing canvas with a lifecycle modeled after a p5.js sketch.
///
/// Subclass `P5Sketch`, override ``setup()`` and ``draw()``, then place ``view``
/// in an AppKit or UIKit view hierarchy.
@MainActor
open class P5Sketch {
    private let internalView: P5SketchInternalView
    var randomGenerator = P5RandomGenerator()
    var noiseGenerator = P5NoiseGenerator()
    var currentAngleMode = P5AngleMode.radians
    var shapeCommands: [P5PathCommand] = []
    var isBuildingShape = false
    var isInsideContour = false
    var shapeHasEndpoint = false
    var colorConfiguration = P5ColorConfiguration()

    /// A human-readable title that clients can use when presenting the sketch.
    public var title: String?

    /// The canvas width in points.
    public let width: CGFloat

    /// The canvas height in points.
    public let height: CGFloat

    /// The native view that displays the sketch.
    ///
    /// ```swift
    /// let sketch = MySketch(size: view.bounds.size)
    /// view.addSubview(sketch.view)
    /// ```
    public var view: P5CanvasView {
        internalView
    }

    /// Creates a sketch with a fixed canvas size.
    ///
    /// The initializer invokes ``setup()`` after the canvas is ready.
    ///
    /// - Parameter size: The canvas size in points.
    public init(size: CGSize) {
        internalView = P5SketchInternalView(size: size)
        width = size.width
        height = size.height
        internalView.onDraw = { [weak self] in
            self?.draw()
        }
        setup()
    }

    /// Creates a sketch with a fixed canvas size.
    ///
    /// - Parameter size: The canvas size in points.
    @available(*, deprecated, renamed: "init(size:)")
    public convenience init(ofSize size: CGSize) {
        self.init(size: size)
    }

    /// Configures the sketch once after initialization.
    ///
    /// Override this method to set the frame rate, drawing styles, and initial
    /// sketch state. This method corresponds to
    /// [p5.js `setup()`](https://p5js.org/reference/p5/setup/).
    open func setup() {}

    /// Updates and draws one frame of the sketch.
    ///
    /// This method corresponds to
    /// [p5.js `draw()`](https://p5js.org/reference/p5/draw/).
    open func draw() {}

    func queueOperation(_ operation: P5Operation) {
        internalView.addOperation(operation)
    }
}

// MARK: - Environment

public extension P5Sketch {
    /// Sets the target number of frames drawn each second.
    ///
    /// This method corresponds to
    /// [p5.js `frameRate()`](https://p5js.org/reference/p5/frameRate/).
    ///
    /// - Parameter framesPerSecond: A finite value greater than zero.
    func frameRate(_ framesPerSecond: Double) {
        precondition(framesPerSecond.isFinite && framesPerSecond > 0)
        internalView.framesPerSecond = framesPerSecond
    }

    /// Creates a vector for positions, motion, and creative-coding math.
    ///
    /// This method corresponds to
    /// [p5.js `createVector()`](https://p5js.org/reference/p5/createVector/).
    ///
    /// - Parameters:
    ///   - x: The x component.
    ///   - y: The y component.
    ///   - z: The z component.
    /// - Returns: A value-semantic ``P5Vector``.
    func createVector(
        _ x: CGFloat = 0,
        _ y: CGFloat = 0,
        _ z: CGFloat = 0
    ) -> P5Vector {
        P5Vector(x: x, y: y, z: z)
    }
}

// MARK: - Structure

public extension P5Sketch {
    /// Saves the current drawing style and transformation state.
    ///
    /// This method corresponds to
    /// [p5.js `push()`](https://p5js.org/reference/p5/push/).
    func push() {
        internalView.addOperation(.push)
    }

    /// Restores the most recently saved drawing state.
    ///
    /// This method corresponds to
    /// [p5.js `pop()`](https://p5js.org/reference/p5/pop/).
    func pop() {
        internalView.addOperation(.pop)
    }

    /// Resumes the draw loop.
    ///
    /// This method corresponds to
    /// [p5.js `loop()`](https://p5js.org/reference/p5/loop/).
    func loop() {
        internalView.isLooping = true
    }

    /// Pauses the draw loop after the current frame.
    ///
    /// This method corresponds to
    /// [p5.js `noLoop()`](https://p5js.org/reference/p5/noLoop/).
    func noLoop() {
        internalView.isLooping = false
    }

    /// Requests one frame while the draw loop is paused.
    ///
    /// This method corresponds to
    /// [p5.js `redraw()`](https://p5js.org/reference/p5/redraw/).
    func redraw() {
        if !internalView.isLooping {
            internalView.userWantsRedraw = true
        }
    }
}

// MARK: - 2D primitives

public extension P5Sketch {
    /// Paints the entire canvas with a color.
    ///
    /// This method corresponds to
    /// [p5.js `background()`](https://p5js.org/reference/p5/background/).
    ///
    /// - Parameter color: The background color.
    func background(_ color: CGColor) {
        internalView.addOperation(.background(color))
    }

    /// Draws a line between two points.
    ///
    /// This method corresponds to
    /// [p5.js `line()`](https://p5js.org/reference/p5/line/).
    ///
    /// - Parameters:
    ///   - x1: The first point's x-coordinate.
    ///   - y1: The first point's y-coordinate.
    ///   - x2: The second point's x-coordinate.
    ///   - y2: The second point's y-coordinate.
    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        internalView.addOperation(.line(x1: x1, y1: y1, x2: x2, y2: y2))
    }

    /// Draws a rectangle from its top-left corner.
    ///
    /// This method corresponds to
    /// [p5.js `rect()`](https://p5js.org/reference/p5/rect/).
    ///
    /// - Parameters:
    ///   - x: The top-left x-coordinate.
    ///   - y: The top-left y-coordinate.
    ///   - width: The rectangle width.
    ///   - height: The rectangle height.
    func rect(
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat
    ) {
        internalView.addOperation(
            .rect(x: x, y: y, width: width, height: height)
        )
    }

    /// Draws a square from its top-left corner.
    ///
    /// This method corresponds to
    /// [p5.js `square()`](https://p5js.org/reference/p5/square/).
    ///
    /// - Parameters:
    ///   - x: The top-left x-coordinate.
    ///   - y: The top-left y-coordinate.
    ///   - extent: The width and height.
    func square(_ x: CGFloat, _ y: CGFloat, _ extent: CGFloat) {
        internalView.addOperation(.square(x: x, y: y, extent: extent))
    }

    /// Draws a circle centered at a point.
    ///
    /// As in p5.js, `diameter` is the full width of the circle, not its radius.
    /// This method corresponds to
    /// [p5.js `circle()`](https://p5js.org/reference/p5/circle/).
    ///
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - diameter: The circle diameter.
    func circle(_ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) {
        ellipse(x, y, diameter, diameter)
    }

    /// Draws an ellipse centered at a point.
    ///
    /// This method corresponds to
    /// [p5.js `ellipse()`](https://p5js.org/reference/p5/ellipse/).
    ///
    /// - Parameters:
    ///   - x: The center x-coordinate.
    ///   - y: The center y-coordinate.
    ///   - width: The ellipse width.
    ///   - height: The ellipse height.
    func ellipse(
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat
    ) {
        internalView.addOperation(
            .ellipse(x: x, y: y, width: width, height: height)
        )
    }

    /// Draws a point using the current stroke color and weight.
    func point(_ x: CGFloat, _ y: CGFloat) {
        internalView.addOperation(.point(x: x, y: y))
    }

    /// Draws a triangle from three vertices.
    func triangle(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat,
        _ x3: CGFloat,
        _ y3: CGFloat
    ) {
        internalView.addOperation(
            .polygon([
                CGPoint(x: x1, y: y1),
                CGPoint(x: x2, y: y2),
                CGPoint(x: x3, y: y3),
            ])
        )
    }

    /// Draws a quadrilateral from four vertices.
    func quad(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat,
        _ x3: CGFloat,
        _ y3: CGFloat,
        _ x4: CGFloat,
        _ y4: CGFloat
    ) {
        internalView.addOperation(
            .polygon([
                CGPoint(x: x1, y: y1),
                CGPoint(x: x2, y: y2),
                CGPoint(x: x3, y: y3),
                CGPoint(x: x4, y: y4),
            ])
        )
    }

    /// Draws an elliptical arc using angles in the current angle mode.
    func arc(
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat,
        _ start: CGFloat,
        _ stop: CGFloat,
        _ mode: P5ArcMode = .open
    ) {
        internalView.addOperation(
            .arc(
                x: x,
                y: y,
                width: width,
                height: height,
                start: currentAngleMode.radians(from: start),
                stop: currentAngleMode.radians(from: stop),
                mode: mode
            )
        )
    }

    /// Draws a rectangle with uniformly rounded corners.
    func rect(
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat,
        cornerRadius: CGFloat
    ) {
        internalView.addOperation(
            .roundedRect(
                x: x,
                y: y,
                width: width,
                height: height,
                cornerRadius: cornerRadius
            )
        )
    }

    /// Draws a regular polygon centered at a point.
    func regularPolygon(
        _ x: CGFloat,
        _ y: CGFloat,
        radius: CGFloat,
        sides: Int,
        rotation: CGFloat = 0
    ) {
        precondition(sides >= 3)
        precondition(radius.isFinite && radius >= 0)
        let start = currentAngleMode.radians(from: rotation)
        let points = (0..<sides).map { index in
            let angle = start + (2 * .pi * CGFloat(index) / CGFloat(sides))
            return CGPoint(x: x + cos(angle) * radius, y: y + sin(angle) * radius)
        }
        internalView.addOperation(.polygon(points))
    }
}

// MARK: - Transformations

public extension P5Sketch {
    /// Rotates the coordinate system by an angle in the current angle mode.
    ///
    /// This method corresponds to
    /// [p5.js `rotate()`](https://p5js.org/reference/p5/rotate/).
    ///
    /// - Parameter angle: The clockwise rotation.
    func rotate(_ angle: CGFloat) {
        internalView.addOperation(.rotate(currentAngleMode.radians(from: angle)))
    }

    /// Moves the origin of the coordinate system.
    ///
    /// This method corresponds to
    /// [p5.js `translate()`](https://p5js.org/reference/p5/translate/).
    ///
    /// - Parameters:
    ///   - x: The horizontal translation.
    ///   - y: The vertical translation.
    func translate(_ x: CGFloat, _ y: CGFloat) {
        internalView.addOperation(.translate(x: x, y: y))
    }

    /// Scales both coordinate axes by the same factor.
    func scale(_ factor: CGFloat) {
        scale(factor, factor)
    }

    /// Scales the horizontal and vertical coordinate axes independently.
    func scale(_ x: CGFloat, _ y: CGFloat) {
        internalView.addOperation(.scale(x: x, y: y))
    }

    /// Shears the horizontal axis by an angle in the current angle mode.
    func shearX(_ angle: CGFloat) {
        internalView.addOperation(.shearX(tan(currentAngleMode.radians(from: angle))))
    }

    /// Shears the vertical axis by an angle in the current angle mode.
    func shearY(_ angle: CGFloat) {
        internalView.addOperation(.shearY(tan(currentAngleMode.radians(from: angle))))
    }

    /// Concatenates a Core Graphics affine transformation.
    func applyMatrix(_ transform: CGAffineTransform) {
        internalView.addOperation(.applyMatrix(transform))
    }

    /// Restores the coordinate system used at the beginning of the frame.
    func resetMatrix() {
        internalView.addOperation(.resetMatrix)
    }
}

// MARK: - Settings

public extension P5Sketch {
    /// Sets the fill color used for closed shapes.
    ///
    /// This method corresponds to
    /// [p5.js `fill()`](https://p5js.org/reference/p5/fill/).
    ///
    /// - Parameter color: The fill color.
    func fill(_ color: CGColor) {
        internalView.addOperation(.fill(color))
    }

    /// Disables filling for subsequently drawn shapes.
    ///
    /// This method corresponds to
    /// [p5.js `noFill()`](https://p5js.org/reference/p5/noFill/).
    func noFill() {
        internalView.addOperation(.noFill)
    }

    /// Sets the stroke color used for lines and shape outlines.
    ///
    /// This method corresponds to
    /// [p5.js `stroke()`](https://p5js.org/reference/p5/stroke/).
    ///
    /// - Parameter color: The stroke color.
    func stroke(_ color: CGColor) {
        internalView.addOperation(.stroke(color))
    }

    /// Disables strokes for subsequently drawn lines and shapes.
    ///
    /// This method corresponds to
    /// [p5.js `noStroke()`](https://p5js.org/reference/p5/noStroke/).
    func noStroke() {
        internalView.addOperation(.noStroke)
    }

    /// Sets the stroke width in points.
    ///
    /// This method corresponds to
    /// [p5.js `strokeWeight()`](https://p5js.org/reference/p5/strokeWeight/).
    ///
    /// - Parameter weight: A finite value greater than zero.
    func strokeWeight(_ weight: CGFloat) {
        precondition(weight.isFinite && weight > 0)
        internalView.addOperation(.strokeWeight(weight))
    }
}
