import CoreGraphics
import Foundation

/// A native drawing canvas with a lifecycle modeled after a p5.js sketch.
///
/// Subclass `P5Sketch`, override ``setup()`` and ``draw()``, then place ``view``
/// in an AppKit or UIKit view hierarchy.
@MainActor
open class P5Sketch {
    private let internalView: P5SketchInternalView
    private let clock: any P5Clock
    private let clockOrigin: TimeInterval
    private var previousFrameTime: TimeInterval
    /// The sketch's copyable and serializable random state.
    ///
    /// Assign an explicitly seeded or previously archived generator before drawing
    /// to inject a reproducible sequence.
    public var randomGenerator: P5RandomGenerator
    var noiseGenerator = P5NoiseGenerator()
    var currentAngleMode = P5AngleMode.radians
    var shapeCommands: [P5PathCommand] = []
    var isBuildingShape = false
    var isInsideContour = false
    var shapeHasEndpoint = false
    var colorConfiguration = P5ColorConfiguration()
    var currentRectMode = P5RectMode.corner
    var currentEllipseMode = P5EllipseMode.center
    var currentImageMode = P5ImageMode.corner
    var currentTransformValue = P5Transform.identity
    var transformStack: [P5Transform] = []
    var currentTextConfiguration = P5TextConfiguration()
    var textConfigurationStack: [P5TextConfiguration] = []

    /// A human-readable title that clients can use when presenting the sketch.
    public var title: String?

    /// The canvas width in points.
    public private(set) var width: CGFloat

    /// The canvas height in points.
    public private(set) var height: CGFloat

    /// The source of frame requests for this sketch.
    public let frameDriver: P5FrameDriver

    /// The most recent pointer position in top-left-origin canvas points.
    public private(set) var pointerPosition = CGPoint.zero

    /// The pointer position preceding ``pointerPosition``.
    public private(set) var previousPointerPosition = CGPoint.zero

    /// Movement between the two most recent pointer positions.
    public private(set) var pointerDelta = CGVector.zero

    /// All pointer buttons currently held.
    public private(set) var pressedPointerButtons: P5PointerButtons = []

    /// Whether the mouse cursor is currently within the canvas.
    public private(set) var isPointerInside = false

    /// The most recently delivered pointer event, if one exists.
    public private(set) var latestPointerEvent: P5PointerEvent?

    /// Active direct, Pencil, and indirect touches sorted by stable identifier.
    public private(set) var touches: [P5Touch] = []

    /// Most recently delivered deterministic multi-touch update.
    public private(set) var latestTouchEvent: P5TouchEvent?

    /// The semantic keys currently held down.
    public private(set) var pressedKeys: Set<P5Key> = []

    /// The most recently delivered keyboard event, if one exists.
    public private(set) var latestKeyboardEvent: P5KeyboardEvent?

    /// Whether at least one semantic key is currently held.
    public var isKeyPressed: Bool {
        !pressedKeys.isEmpty
    }

    /// The number of frames whose `draw()` callback has begun.
    public private(set) var frameCount: UInt64 = 0

    /// The elapsed time between the two most recent frames, in milliseconds.
    ///
    /// The value is zero before the first frame and whenever two manual frames
    /// are requested without advancing their clock.
    public private(set) var deltaTime = 0.0

    /// Current user-space affine transformation for queued drawing operations.
    public var currentTransform: P5Transform {
        currentTransformValue
    }

    private var measuredFramesPerSecond = 0.0
    private var loopsWhenActive = true
    private var activeTouchesByID: [UInt64: P5Touch] = [:]

    /// Current host gesture recognizer cooperation policy.
    public private(set) var gestureCoexistenceMode = P5GestureCoexistence.nativeDefault

    /// Whether automatic frame delivery is suspended for scene or application lifecycle.
    public private(set) var isPaused = false

    /// Most recently applied application visibility state.
    public private(set) var scenePhase = P5ScenePhase.active

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
    public convenience init(size: CGSize) {
        self.init(
            size: size,
            clock: P5SystemClock(),
            frameDriver: .automatic,
            randomGenerator: P5RandomGenerator()
        )
    }

    /// Creates a sketch with an explicit clock and frame driver.
    ///
    /// Use ``P5ManualClock`` with ``P5FrameDriver/manual`` when a sketch must
    /// produce repeatable timing in a test, preview, export, or simulation.
    ///
    /// - Parameters:
    ///   - size: The canvas size in points.
    ///   - clock: A finite monotonic clock. The sketch measures elapsed time
    ///     relative to its value during initialization.
    ///   - frameDriver: The source of frame requests.
    ///   - randomGenerator: Initial copyable random state for the sketch.
    public init(
        size: CGSize,
        clock: any P5Clock,
        frameDriver: P5FrameDriver,
        randomGenerator: P5RandomGenerator = P5RandomGenerator()
    ) {
        precondition(
            size.width.isFinite && size.width > 0 && size.height.isFinite && size.height > 0
        )
        let initialTime = clock.now
        precondition(initialTime.isFinite)
        self.clock = clock
        clockOrigin = initialTime
        previousFrameTime = initialTime
        self.frameDriver = frameDriver
        self.randomGenerator = randomGenerator
        internalView = P5SketchInternalView(
            size: size,
            automaticallyDriven: frameDriver == .automatic
        )
        width = size.width
        height = size.height
        internalView.onDraw = { [weak self] in
            self?.performFrame()
        }
        internalView.onPointerEvent = { [weak self] event in
            self?.handlePointerEvent(event)
        }
        internalView.onKeyboardEvent = { [weak self] event in
            self?.handleKeyboardEvent(event)
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

    /// Responds when a pointer enters the canvas.
    open func pointerEntered(_ event: P5PointerEvent) {}

    /// Responds when a pointer exits the canvas.
    open func pointerExited(_ event: P5PointerEvent) {}

    /// Responds when an unpressed pointer moves across the canvas.
    open func pointerMoved(_ event: P5PointerEvent) {}

    /// Responds when a pressed pointer moves across the canvas.
    open func pointerDragged(_ event: P5PointerEvent) {}

    /// Responds when a pointer button or touch becomes pressed.
    open func pointerPressed(_ event: P5PointerEvent) {}

    /// Responds when a pointer button or touch is released.
    open func pointerReleased(_ event: P5PointerEvent) {}

    /// Responds after a complete click or tap.
    open func pointerClicked(_ event: P5PointerEvent) {}

    /// Responds when the platform cancels an active pointer interaction.
    open func pointerCancelled(_ event: P5PointerEvent) {}

    /// Responds to every ordered multi-touch collection update.
    open func touchesChanged(_ event: P5TouchEvent) {}

    /// Responds when a touch becomes active.
    open func touchesStarted(_ event: P5TouchEvent) {}

    /// Responds when an active touch changes position or pressure.
    open func touchesMoved(_ event: P5TouchEvent) {}

    /// Responds when a touch ends normally.
    open func touchesEnded(_ event: P5TouchEvent) {}

    /// Responds when the platform cancels a touch.
    open func touchesCancelled(_ event: P5TouchEvent) {}

    /// Responds when a keyboard key becomes pressed or repeats.
    open func keyPressed(_ event: P5KeyboardEvent) {}

    /// Responds when a keyboard key is released.
    open func keyReleased(_ event: P5KeyboardEvent) {}

    /// Responds when a key produces printable text.
    open func keyTyped(_ event: P5KeyboardEvent) {}

    /// Responds when the platform cancels an active key interaction.
    open func keyCancelled(_ event: P5KeyboardEvent) {}

    private func performFrame() {
        let currentTime = clock.now
        precondition(currentTime.isFinite && currentTime >= previousFrameTime)
        let elapsed = currentTime - previousFrameTime
        deltaTime = elapsed * 1_000
        measuredFramesPerSecond = elapsed > 0 ? 1 / elapsed : 0
        previousFrameTime = currentTime
        precondition(frameCount < .max)
        frameCount += 1
        currentTransformValue = .identity
        transformStack.removeAll(keepingCapacity: true)
        textConfigurationStack.removeAll(keepingCapacity: true)
        draw()
    }

    private func handlePointerEvent(_ event: P5PointerEvent) {
        previousPointerPosition = event.previousLocation
        pointerPosition = event.location
        pointerDelta = event.delta
        pressedPointerButtons = event.pressedButtons
        latestPointerEvent = event
        let touchEvent = updateTouchState(from: event)

        switch event.phase {
        case .entered:
            isPointerInside = true
            pointerEntered(event)
        case .exited:
            isPointerInside = false
            pointerExited(event)
        case .moved:
            pointerMoved(event)
        case .dragged:
            pointerDragged(event)
        case .pressed:
            pointerPressed(event)
        case .released:
            pointerReleased(event)
        case .clicked:
            pointerClicked(event)
        case .cancelled:
            pressedPointerButtons = []
            pointerCancelled(event)
        }
        if let touchEvent {
            dispatchTouchEvent(touchEvent)
        }
    }

    private func updateTouchState(from event: P5PointerEvent) -> P5TouchEvent? {
        guard event.kind != .mouse else { return nil }
        let touch = P5Touch(pointerEvent: event)
        let phase: P5TouchPhase
        switch event.phase {
        case .pressed:
            activeTouchesByID[event.id] = touch
            phase = .started
        case .moved, .dragged:
            activeTouchesByID[event.id] = touch
            phase = .moved
        case .released:
            activeTouchesByID[event.id] = nil
            phase = .ended
        case .cancelled:
            activeTouchesByID[event.id] = nil
            phase = .cancelled
        case .entered, .exited, .clicked:
            return nil
        }
        touches = activeTouchesByID.values.sorted { $0.id < $1.id }
        return P5TouchEvent(
            phase: phase,
            changedTouches: [touch],
            activeTouches: touches,
            modifiers: event.modifiers,
            timestamp: event.timestamp
        )
    }

    private func dispatchTouchEvent(_ event: P5TouchEvent) {
        latestTouchEvent = event
        touchesChanged(event)
        switch event.phase {
        case .started:
            touchesStarted(event)
        case .moved:
            touchesMoved(event)
        case .ended:
            touchesEnded(event)
        case .cancelled:
            touchesCancelled(event)
        }
    }

    private func handleKeyboardEvent(_ event: P5KeyboardEvent) {
        latestKeyboardEvent = event
        switch event.phase {
        case .pressed:
            pressedKeys.insert(event.key)
            keyPressed(event)
        case .released:
            pressedKeys.remove(event.key)
            keyReleased(event)
        case .typed:
            keyTyped(event)
        case .cancelled:
            pressedKeys.remove(event.key)
            keyCancelled(event)
        }
    }

    func queueOperation(_ operation: P5Operation) {
        internalView.addOperation(operation)
    }

    func renderQueuedOperations(in context: CGContext) {
        internalView.renderQueuedOperations(in: context)
    }
}

// MARK: - Environment

public extension P5Sketch {
    /// Selects how existing host gesture recognizers interact with UIKit touches.
    func gestureCoexistence(_ mode: P5GestureCoexistence) {
        gestureCoexistenceMode = mode
        internalView.gestureCoexistence = mode
    }

    /// Returns whether a semantic key is currently held.
    func keyIsDown(_ key: P5Key) -> Bool {
        pressedKeys.contains(key)
    }

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

    /// Returns the measured rate of the most recently drawn frame.
    ///
    /// The value is zero before the first frame or when no clock time elapsed
    /// between two manual frames.
    func frameRate() -> Double {
        measuredFramesPerSecond
    }

    /// Returns milliseconds elapsed since this sketch was initialized.
    ///
    /// Unlike wall-clock time, this value cannot be affected by clock changes,
    /// time zones, or device sleep corrections.
    func millis() -> Double {
        let currentTime = clock.now
        precondition(currentTime.isFinite && currentTime >= clockOrigin)
        return (currentTime - clockOrigin) * 1_000
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
        transformStack.append(currentTransformValue)
        textConfigurationStack.append(currentTextConfiguration)
        internalView.addOperation(.push)
    }

    /// Restores the most recently saved drawing state.
    ///
    /// This method corresponds to
    /// [p5.js `pop()`](https://p5js.org/reference/p5/pop/).
    func pop() {
        if let transform = transformStack.popLast() {
            currentTransformValue = transform
        }
        if let configuration = textConfigurationStack.popLast() {
            currentTextConfiguration = configuration
        }
        internalView.addOperation(.pop)
    }

    /// Resumes the draw loop.
    ///
    /// This method corresponds to
    /// [p5.js `loop()`](https://p5js.org/reference/p5/loop/).
    func loop() {
        loopsWhenActive = true
        if !isPaused {
            internalView.isLooping = true
        }
    }

    /// Pauses the draw loop after the current frame.
    ///
    /// This method corresponds to
    /// [p5.js `noLoop()`](https://p5js.org/reference/p5/noLoop/).
    func noLoop() {
        loopsWhenActive = false
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

    /// Requests one frame from a manually driven sketch.
    ///
    /// The method synchronously updates timing and invokes ``draw()``. The native
    /// view presents the queued drawing operations on its next display pass.
    /// Advance a ``P5ManualClock`` first to control ``deltaTime``.
    func advanceFrame() {
        precondition(frameDriver == .manual)
        performFrame()
        internalView.requestManualFrame()
    }

    /// Suspends automatic frame delivery while preserving the user's loop preference.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        internalView.isLooping = false
    }

    /// Resumes automatic frame delivery when the sketch was configured to loop.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        internalView.isLooping = loopsWhenActive
    }

    /// Applies a native scene or window lifecycle transition.
    ///
    /// Inactive and background scenes pause automatic frames. Returning to active
    /// resumes only sketches whose loop preference was enabled.
    func scenePhaseChanged(to phase: P5ScenePhase) {
        scenePhase = phase
        switch phase {
        case .active:
            resume()
        case .inactive, .background:
            pause()
        }
    }

    /// Changes the logical canvas extent and native view bounds.
    ///
    /// Existing queued drawing commands retain their coordinates. The resize does not
    /// scale or preserve pixels already presented by the native view.
    ///
    /// - Parameters:
    ///   - width: A finite positive width in points.
    ///   - height: A finite positive height in points.
    func resizeCanvas(_ width: CGFloat, _ height: CGFloat) {
        precondition(width.isFinite && width > 0 && height.isFinite && height > 0)
        self.width = width
        self.height = height
        internalView.resize(to: CGSize(width: width, height: height))
    }

    /// Sets the requested canvas raster density multiplier.
    ///
    /// - Parameter density: A finite positive number of raster pixels per canvas point.
    func pixelDensity(_ density: CGFloat) {
        precondition(density.isFinite && density > 0)
        internalView.pixelDensity = density
    }

    /// Returns the requested canvas raster density multiplier.
    func pixelDensity() -> CGFloat {
        internalView.pixelDensity
    }

    /// Returns current canvas, native display, safe-area, and full-screen metadata.
    func canvasMetrics() -> P5CanvasMetrics {
        internalView.canvasMetrics()
    }

    /// Renders queued commands into an immutable image without consuming them.
    ///
    /// - Parameter pixelDensity: Optional capture density; the canvas density is the default.
    /// - Returns: A top-left-origin snapshot suitable for pixels or export.
    /// - Throws: ``P5ImageError/bitmapAllocationFailed`` when Core Graphics
    ///   cannot allocate or snapshot the capture bitmap.
    func captureFrame(pixelDensity: CGFloat? = nil) throws -> P5Image {
        try internalView.capture(pixelDensity: pixelDensity ?? internalView.pixelDensity)
    }
}

// MARK: - 2D primitives

public extension P5Sketch {
    /// Removes every pixel from the canvas to transparent black.
    func clear() {
        internalView.addOperation(.clear)
    }

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
        let rectangle = rectangle(x, y, width, height)
        internalView.addOperation(
            .rect(
                x: rectangle.origin.x,
                y: rectangle.origin.y,
                width: rectangle.size.width,
                height: rectangle.size.height
            )
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
        rect(x, y, extent, extent)
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
        let rectangle = ellipseRectangle(x, y, width, height)
        internalView.addOperation(
            .ellipse(
                x: rectangle.midX,
                y: rectangle.midY,
                width: rectangle.width,
                height: rectangle.height
            )
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
        let rectangle = ellipseRectangle(x, y, width, height)
        internalView.addOperation(
            .arc(
                x: rectangle.midX,
                y: rectangle.midY,
                width: rectangle.width,
                height: rectangle.height,
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
        let rectangle = rectangle(x, y, width, height)
        internalView.addOperation(
            .roundedRect(
                x: rectangle.origin.x,
                y: rectangle.origin.y,
                width: rectangle.size.width,
                height: rectangle.size.height,
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

    private func rectangle(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ fourth: CGFloat
    ) -> CGRect {
        switch currentRectMode {
        case .corner:
            return CGRect(x: first, y: second, width: third, height: fourth)
        case .corners:
            return CGRect(
                x: min(first, third),
                y: min(second, fourth),
                width: abs(third - first),
                height: abs(fourth - second)
            )
        case .center:
            return CGRect(
                x: first - third / 2,
                y: second - fourth / 2,
                width: third,
                height: fourth
            )
        case .radius:
            return CGRect(
                x: first - third,
                y: second - fourth,
                width: third * 2,
                height: fourth * 2
            )
        }
    }

    private func ellipseRectangle(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ fourth: CGFloat
    ) -> CGRect {
        switch currentEllipseMode {
        case .corner:
            return CGRect(x: first, y: second, width: third, height: fourth)
        case .corners:
            return CGRect(
                x: min(first, third),
                y: min(second, fourth),
                width: abs(third - first),
                height: abs(fourth - second)
            )
        case .center:
            return CGRect(
                x: first - third / 2,
                y: second - fourth / 2,
                width: third,
                height: fourth
            )
        case .radius:
            return CGRect(
                x: first - third,
                y: second - fourth,
                width: third * 2,
                height: fourth * 2
            )
        }
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
        let radians = currentAngleMode.radians(from: angle)
        currentTransformValue = currentTransformValue.rotated(by: radians)
        internalView.addOperation(.rotate(radians))
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
        currentTransformValue = currentTransformValue.translatedBy(x: x, y: y)
        internalView.addOperation(.translate(x: x, y: y))
    }

    /// Scales both coordinate axes by the same factor.
    func scale(_ factor: CGFloat) {
        scale(factor, factor)
    }

    /// Scales the horizontal and vertical coordinate axes independently.
    func scale(_ x: CGFloat, _ y: CGFloat) {
        currentTransformValue = currentTransformValue.scaledBy(x: x, y: y)
        internalView.addOperation(.scale(x: x, y: y))
    }

    /// Shears the horizontal axis by an angle in the current angle mode.
    func shearX(_ angle: CGFloat) {
        let amount = tan(currentAngleMode.radians(from: angle))
        let transform = P5Transform(a: 1, b: 0, c: amount, d: 1)
        currentTransformValue = currentTransformValue.concatenating(transform)
        internalView.addOperation(.shearX(amount))
    }

    /// Shears the vertical axis by an angle in the current angle mode.
    func shearY(_ angle: CGFloat) {
        let amount = tan(currentAngleMode.radians(from: angle))
        let transform = P5Transform(a: 1, b: amount, c: 0, d: 1)
        currentTransformValue = currentTransformValue.concatenating(transform)
        internalView.addOperation(.shearY(amount))
    }

    /// Concatenates a Core Graphics affine transformation.
    func applyMatrix(_ transform: CGAffineTransform) {
        applyMatrix(P5Transform(transform))
    }

    /// Concatenates a reusable value-semantic affine transformation.
    func applyMatrix(_ transform: P5Transform) {
        currentTransformValue = currentTransformValue.concatenating(transform)
        internalView.addOperation(.applyMatrix(transform.cgAffineTransform))
    }

    /// Restores the coordinate system used at the beginning of the frame.
    func resetMatrix() {
        currentTransformValue = .identity
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
