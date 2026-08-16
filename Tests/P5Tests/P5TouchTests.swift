import CoreGraphics
import Foundation
import Testing

@testable import P5

@MainActor
@Suite("P5 deterministic multi-touch", .serialized)
struct P5TouchTests {
    @Test("Stable touch identifiers update an ordered active collection and callbacks")
    func collectionAndCallbacks() throws {
        let sketch = RecordingTouchSketch(size: CGSize(width: 100, height: 80))
        let canvas = try #require(sketch.view as? P5SketchInternalView)

        canvas.deliverPointerEvent(event(id: 2, kind: .touch, phase: .entered))
        canvas.deliverPointerEvent(event(id: 2, kind: .touch, phase: .pressed, x: 20))
        canvas.deliverPointerEvent(event(id: 1, kind: .pencil, phase: .pressed, x: 10))
        #expect(sketch.touches.map(\.id) == [1, 2])
        #expect(sketch.receivedPhases == [.started, .started])
        #expect(sketch.changedCallCount == 2)

        canvas.deliverPointerEvent(event(id: 2, kind: .indirect, phase: .moved, x: 21))
        canvas.deliverPointerEvent(event(id: 2, kind: .indirect, phase: .dragged, x: 22))
        #expect(sketch.receivedPhases.suffix(2) == [.moved, .moved])
        #expect(sketch.touches.first { $0.id == 2 }?.location.x == 22)

        canvas.deliverPointerEvent(event(id: 1, kind: .pencil, phase: .released, x: 11))
        canvas.deliverPointerEvent(event(id: 1, kind: .pencil, phase: .clicked, x: 11))
        canvas.deliverPointerEvent(event(id: 2, kind: .touch, phase: .cancelled, x: 22))
        canvas.deliverPointerEvent(event(id: 2, kind: .touch, phase: .exited, x: 22))
        #expect(sketch.touches.isEmpty)
        #expect(sketch.receivedPhases.suffix(2) == [.ended, .cancelled])
        #expect(sketch.latestTouchEvent?.phase == .cancelled)
        #expect(sketch.latestTouchEvent?.activeTouches.isEmpty == true)

        sketch.gestureCoexistence(.cooperative)
        #expect(sketch.gestureCoexistenceMode == .cooperative)
        #expect(canvas.gestureCoexistence == .cooperative)
        sketch.gestureCoexistence(.nativeDefault)
        #expect(P5GestureCoexistence.allCases == [.nativeDefault, .cooperative])
        #expect(P5TouchPhase.allCases == [.started, .moved, .ended, .cancelled])

        let baseSketch = P5Sketch(size: CGSize(width: 10, height: 10))
        let baseCanvas = try #require(baseSketch.view as? P5SketchInternalView)
        baseCanvas.deliverPointerEvent(event(id: 9, kind: .touch, phase: .pressed))
        baseCanvas.deliverPointerEvent(event(id: 9, kind: .touch, phase: .moved))
        baseCanvas.deliverPointerEvent(event(id: 9, kind: .touch, phase: .released))
        baseCanvas.deliverPointerEvent(event(id: 10, kind: .touch, phase: .pressed))
        baseCanvas.deliverPointerEvent(event(id: 10, kind: .touch, phase: .cancelled))
    }

    @Test("Touch values and collection events serialize for deterministic replay")
    func serialization() throws {
        let first = P5Touch(
            id: 2,
            kind: .touch,
            location: CGPoint(x: 4, y: 5),
            previousLocation: CGPoint(x: 1, y: 2),
            pressure: 0.5,
            timestamp: 3
        )
        let second = P5Touch(
            id: 1,
            kind: .pencil,
            location: CGPoint(x: 8, y: 9),
            previousLocation: CGPoint(x: 7, y: 7),
            timestamp: 3
        )
        #expect(first.delta == CGVector(dx: 3, dy: 3))
        #expect(
            try JSONDecoder().decode(
                P5Touch.self,
                from: JSONEncoder().encode(first)
            ) == first
        )
        let event = P5TouchEvent(
            phase: .moved,
            changedTouches: [first, second],
            activeTouches: [first, second],
            modifiers: [.shift],
            timestamp: 99
        )
        #expect(event.changedTouches.map(\.id) == [1, 2])
        #expect(event.activeTouches.map(\.id) == [1, 2])
        #expect(
            try JSONDecoder().decode(
                P5TouchEvent.self,
                from: JSONEncoder().encode(event)
            ) == event
        )

        let touchJSON = try #require(String(data: JSONEncoder().encode(first), encoding: .utf8))
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                P5Touch.self,
                from: Data(touchJSON.replacingOccurrences(of: "\"touch\"", with: "\"mouse\"").utf8)
            )
        }
        let eventJSON = try #require(String(data: JSONEncoder().encode(event), encoding: .utf8))
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                P5TouchEvent.self,
                from: Data(
                    eventJSON.replacingOccurrences(
                        of: "\"timestamp\":99", with: "\"timestamp\":-1"
                    )
                    .utf8)
            )
        }
    }

    @Test("Invalid touch values terminate at public boundaries")
    nonisolated func invalidValuesTerminateTheProcess() async {
        await #expect(processExitsWith: .failure) {
            _ = P5Touch(
                id: 1,
                kind: .mouse,
                location: .zero,
                previousLocation: .zero,
                timestamp: 0
            )
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Touch(
                id: 1,
                kind: .touch,
                location: CGPoint(x: CGFloat.nan, y: 0),
                previousLocation: .zero,
                timestamp: 0
            )
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Touch(
                id: 1,
                kind: .touch,
                location: .zero,
                previousLocation: CGPoint(x: 0, y: CGFloat.infinity),
                pressure: 2,
                timestamp: 0
            )
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Touch(
                id: 1,
                kind: .touch,
                location: .zero,
                previousLocation: .zero,
                timestamp: -1
            )
        }
        await #expect(processExitsWith: .failure) {
            _ = P5TouchEvent(
                phase: .started,
                changedTouches: [],
                activeTouches: [],
                timestamp: 0
            )
        }
        await #expect(processExitsWith: .failure) {
            let touch = P5Touch(
                id: 1,
                kind: .touch,
                location: .zero,
                previousLocation: .zero,
                timestamp: 0
            )
            _ = P5TouchEvent(
                phase: .moved,
                changedTouches: [touch, touch],
                activeTouches: [touch],
                timestamp: 0
            )
        }
        await #expect(processExitsWith: .failure) {
            let touch = P5Touch(
                id: 1,
                kind: .touch,
                location: .zero,
                previousLocation: .zero,
                timestamp: 0
            )
            _ = P5TouchEvent(
                phase: .moved,
                changedTouches: [touch],
                activeTouches: [touch, touch],
                timestamp: .nan
            )
        }
    }

    private func event(
        id: UInt64,
        kind: P5PointerKind,
        phase: P5PointerPhase,
        x: CGFloat = 0
    ) -> P5PointerEvent {
        P5PointerEvent(
            id: id,
            kind: kind,
            phase: phase,
            location: CGPoint(x: x, y: 4),
            previousLocation: CGPoint(x: x - 1, y: 4),
            button: .primary,
            pressedButtons: phase == .released || phase == .cancelled ? [] : .primary,
            modifiers: [.shift],
            pressure: kind == .indirect ? nil : 0.5,
            timestamp: Double(x + 10)
        )
    }
}

@MainActor
private final class RecordingTouchSketch: P5Sketch {
    private(set) var receivedPhases: [P5TouchPhase] = []
    private(set) var changedCallCount = 0

    override func touchesChanged(_ event: P5TouchEvent) {
        changedCallCount += 1
    }

    override func touchesStarted(_ event: P5TouchEvent) {
        receivedPhases.append(event.phase)
    }

    override func touchesMoved(_ event: P5TouchEvent) {
        receivedPhases.append(event.phase)
    }

    override func touchesEnded(_ event: P5TouchEvent) {
        receivedPhases.append(event.phase)
    }

    override func touchesCancelled(_ event: P5TouchEvent) {
        receivedPhases.append(event.phase)
    }
}
