import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import P5

@MainActor
@Suite(.serialized)
struct P5TimingTests {
    @Test
    func manualClockAndFrameDriverProduceDeterministicMetrics() throws {
        let clock = P5ManualClock(initialTime: 10)
        let sketch = TimingSketch(
            size: CGSize(width: 8, height: 8),
            clock: clock,
            frameDriver: .manual
        )
        let bitmap = try #require(TestBitmap(width: 8, height: 8))

        #expect(sketch.frameDriver == .manual)
        #expect(sketch.frameCount == 0)
        #expect(sketch.deltaTime == 0)
        #expect(sketch.frameRate() == 0)
        #expect(sketch.millis() == 0)

        sketch.advanceFrame()
        #expect(sketch.frameCount == 1)
        #expect(sketch.deltaTime == 0)
        #expect(sketch.frameRate() == 0)
        #expect(sketch.drawCallCount == 1)
        draw(sketch, in: bitmap)

        clock.advance(by: 0.02)
        sketch.advanceFrame()
        draw(sketch, in: bitmap)

        #expect(sketch.frameCount == 2)
        #expect(abs(sketch.deltaTime - 20) < 0.000_001)
        #expect(abs(sketch.frameRate() - 50) < 0.000_001)
        #expect(abs(sketch.millis() - 20) < 0.000_001)
        #expect(sketch.drawCallCount == 2)

        draw(sketch, in: bitmap)
        #expect(sketch.drawCallCount == 2)
    }

    @Test
    func systemClockAndFrameDriverValuesArePublicValueTypes() throws {
        let clock = P5SystemClock()
        let first = clock.now
        let second = clock.now

        #expect(first.isFinite)
        #expect(second >= first)
        #expect(P5FrameDriver.allCases == [.automatic, .manual])
        let data = try JSONEncoder().encode(P5FrameDriver.manual)
        #expect(try JSONDecoder().decode(P5FrameDriver.self, from: data) == .manual)
    }

    @Test
    func invalidClockAndDriverOperationsTerminateTheProcess() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = P5ManualClock(initialTime: -.infinity)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5ManualClock().advance(by: -1)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let clock = P5ManualClock(initialTime: .greatestFiniteMagnitude)
                clock.advance(by: .greatestFiniteMagnitude)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = P5Sketch(
                    size: CGSize(width: 1, height: 1),
                    clock: MutableTestClock(now: .nan),
                    frameDriver: .manual
                )
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let clock = MutableTestClock(now: 2)
                let sketch = P5Sketch(
                    size: CGSize(width: 1, height: 1),
                    clock: clock,
                    frameDriver: .manual
                )
                clock.now = 1
                _ = sketch.millis()
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                P5Sketch(size: CGSize(width: 1, height: 1)).advanceFrame()
            }
        }
    }

    private func draw(_ sketch: P5Sketch, in bitmap: TestBitmap) {
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.current = NSGraphicsContext(
            cgContext: bitmap.context,
            flipped: true
        )
        sketch.view.draw(sketch.view.bounds)
    }
}

@MainActor
private final class TimingSketch: P5Sketch {
    private(set) var drawCallCount = 0

    override func draw() {
        drawCallCount += 1
    }
}

@MainActor
private final class MutableTestClock: P5Clock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}
