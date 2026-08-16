# Timing and Determinism

Drive animation from a monotonic clock, or reproduce frames exactly with a
manual clock.

## Read frame timing

``P5Sketch/frameCount`` starts at zero and increments immediately before each
call to ``P5Sketch/draw()``. ``P5Sketch/deltaTime`` reports the elapsed time
since the previous frame in milliseconds, matching p5.js units. The no-argument
``P5Sketch/frameRate()`` reports the reciprocal of that most recent interval;
``P5Sketch/frameRate(_:)`` continues to set the automatic driver's target.

``P5Sketch/millis()`` measures milliseconds since sketch initialization. It
uses a monotonic time source, so wall-clock adjustments and time-zone changes do
not affect animation.

```swift
override func draw() {
    let seconds = deltaTime / 1_000
    position += velocity * seconds

    if frameCount.isMultiple(of: 60) {
        print("Measured rate: \(frameRate())")
    }
}
```

The first automatic frame measures from sketch initialization. Two frames at
the same clock value have a zero `deltaTime` and measured frame rate.

## Reproduce a frame sequence

Pair ``P5ManualClock`` with ``P5FrameDriver/manual``. An incidental native view
redraw does not execute `draw()` in manual mode. Each call to
``P5Sketch/advanceFrame()`` synchronously updates timing, executes `draw()`, and
requests presentation of the queued operations.

```swift
let clock = P5ManualClock()
let sketch = ParticleSketch(
    size: CGSize(width: 640, height: 480),
    clock: clock,
    frameDriver: .manual
)

for _ in 0..<120 {
    clock.advance(by: 1.0 / 60.0)
    sketch.advanceFrame()
}
```

The native view presents the queued frame on its next display pass. Platform
display requests may coalesce, so export code that needs every intermediate
image should render the native view into a bitmap graphics context after each
call. Keep clock mutation and all sketch access on the main actor.

## Supply another monotonic clock

Conform a type to ``P5Clock`` when time comes from a replay stream or simulation
timeline. Values are seconds from any origin, but they must remain finite and
must never decrease. The sketch traps on a contract violation so corrupted time
cannot silently destabilize a simulation.
