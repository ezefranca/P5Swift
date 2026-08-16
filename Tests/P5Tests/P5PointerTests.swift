import CoreGraphics
import Foundation
import Testing

@testable import P5

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
@Suite(.serialized)
struct P5PointerTests {
    @Test
    func platformNeutralEventsUpdateStateAndDispatchOrderedCallbacks() throws {
        let sketch = RecordingPointerSketch(size: CGSize(width: 100, height: 80))
        let canvas = try #require(sketch.view as? P5SketchInternalView)
        let phases = P5PointerPhase.allCases

        for (index, phase) in phases.enumerated() {
            canvas.deliverPointerEvent(
                makeEvent(
                    phase: phase,
                    location: CGPoint(x: index + 1, y: index + 2),
                    previousLocation: CGPoint(x: index, y: index),
                    pressedButtons: [.primary, .other]
                )
            )
        }

        #expect(sketch.receivedPhases == phases)
        #expect(sketch.pointerPosition == CGPoint(x: 8, y: 9))
        #expect(sketch.previousPointerPosition == CGPoint(x: 7, y: 7))
        #expect(sketch.pointerDelta == CGVector(dx: 1, dy: 2))
        #expect(sketch.pressedPointerButtons.isEmpty)
        #expect(sketch.isPointerInside == false)
        #expect(sketch.latestPointerEvent?.phase == .cancelled)

        let event = makeEvent(
            phase: .dragged,
            location: CGPoint(x: 7, y: 9),
            previousLocation: CGPoint(x: 2, y: 3),
            pressedButtons: [.primary, .secondary, .middle, .other]
        )
        #expect(event.delta == CGVector(dx: 5, dy: 6))
        let encoded = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(P5PointerEvent.self, from: encoded) == event)
        let encodedString = try #require(String(data: encoded, encoding: .utf8))
        let invalidJSON = encodedString.replacingOccurrences(
            of: "\"timestamp\":1",
            with: "\"timestamp\":-1"
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(P5PointerEvent.self, from: Data(invalidJSON.utf8))
        }
        let buttonData = try JSONEncoder().encode(P5PointerButton.other(7))
        #expect(try JSONDecoder().decode(P5PointerButton.self, from: buttonData) == .other(7))
        #expect(P5PointerKind.allCases == [.mouse, .touch, .pencil, .indirect])
        #expect(P5PointerPhase.allCases == phases)

        let baseSketch = P5Sketch(size: CGSize(width: 10, height: 10))
        let baseCanvas = try #require(baseSketch.view as? P5SketchInternalView)
        for phase in phases {
            let eventWithoutPressure = P5PointerEvent(
                id: 0,
                kind: .mouse,
                phase: phase,
                location: .zero,
                previousLocation: .zero,
                timestamp: 0
            )
            baseCanvas.deliverPointerEvent(eventWithoutPressure)
            let eventData = try JSONEncoder().encode(eventWithoutPressure)
            #expect(
                try JSONDecoder().decode(P5PointerEvent.self, from: eventData)
                    == eventWithoutPressure
            )
        }
        #expect(baseSketch.latestPointerEvent?.pressure == nil)
    }

    #if canImport(AppKit)
        @Test
        func appKitAdapterMapsNativeMouseEventsAndHelpers() throws {
            let sketch = RecordingPointerSketch(size: CGSize(width: 100, height: 80))
            let canvas = try #require(sketch.view as? P5SketchInternalView)
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: CGPoint(x: 12, y: 18),
                    modifierFlags: [.shift, .control, .option, .command, .capsLock, .function],
                    timestamp: 3,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 1,
                    clickCount: 1,
                    pressure: 0.5
                )
            )
            let eventWithoutClick = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: CGPoint(x: 13, y: 20),
                    modifierFlags: [],
                    timestamp: 4,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 2,
                    clickCount: 0,
                    pressure: 0
                )
            )

            canvas.updateTrackingAreas()
            canvas.updateTrackingAreas()
            #expect(canvas.acceptsFirstResponder)
            canvas.mouseEntered(with: event)
            canvas.mouseExited(with: event)
            canvas.mouseMoved(with: event)
            canvas.mouseDragged(with: event)
            canvas.rightMouseDragged(with: event)
            canvas.otherMouseDragged(with: event)
            canvas.mouseDown(with: event)
            canvas.rightMouseDown(with: event)
            canvas.otherMouseDown(with: event)
            canvas.mouseUp(with: event)
            canvas.rightMouseUp(with: event)
            canvas.otherMouseUp(with: event)
            canvas.mouseUp(with: eventWithoutClick)

            #expect(sketch.receivedPhases.contains(.entered))
            #expect(sketch.receivedPhases.contains(.exited))
            #expect(sketch.receivedPhases.contains(.moved))
            #expect(sketch.receivedPhases.contains(.dragged))
            #expect(sketch.receivedPhases.contains(.pressed))
            #expect(sketch.receivedPhases.contains(.released))
            #expect(sketch.receivedPhases.contains(.clicked))
            #expect(sketch.latestPointerEvent?.modifiers.isEmpty == true)

            #expect(P5SketchInternalView.pointerButton(forButtonNumber: 0) == .primary)
            #expect(P5SketchInternalView.pointerButton(forButtonNumber: 1) == .secondary)
            #expect(P5SketchInternalView.pointerButton(forButtonNumber: 2) == .middle)
            #expect(P5SketchInternalView.pointerButton(forButtonNumber: 8) == .other(8))
            #expect(
                P5SketchInternalView.pointerButtons(from: 0b1111)
                    == [.primary, .secondary, .middle, .other]
            )
            #expect(
                P5SketchInternalView.modifierKeys(
                    from: [.shift, .control, .option, .command, .capsLock, .function]
                ) == [.shift, .control, .option, .command, .capsLock, .function]
            )
            #expect(P5SketchInternalView.normalizedPressure(-1) == 0)
            #expect(P5SketchInternalView.normalizedPressure(2) == 1)
            #expect(P5SketchInternalView.normalizedPressure(.infinity) == nil)
        }
    #endif

    @Test
    func invalidPointerValuesTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PointerEvent(
                    id: 0,
                    kind: .mouse,
                    phase: .moved,
                    location: CGPoint(x: CGFloat.nan, y: 0),
                    previousLocation: .zero,
                    timestamp: 0
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PointerEvent(
                    id: 0,
                    kind: .mouse,
                    phase: .moved,
                    location: .zero,
                    previousLocation: CGPoint(x: 0, y: CGFloat.infinity),
                    timestamp: 0
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PointerEvent(
                    id: 0,
                    kind: .mouse,
                    phase: .moved,
                    location: .zero,
                    previousLocation: .zero,
                    timestamp: -1
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PointerEvent(
                    id: 0,
                    kind: .mouse,
                    phase: .moved,
                    location: .zero,
                    previousLocation: .zero,
                    pressure: 2,
                    timestamp: 0
                )
            }
        #endif
    }

    private func makeEvent(
        phase: P5PointerPhase,
        location: CGPoint = .zero,
        previousLocation: CGPoint = .zero,
        pressedButtons: P5PointerButtons = []
    ) -> P5PointerEvent {
        P5PointerEvent(
            id: 42,
            kind: .mouse,
            phase: phase,
            location: location,
            previousLocation: previousLocation,
            button: .primary,
            pressedButtons: pressedButtons,
            modifiers: [.shift, .option],
            pressure: 0.75,
            timestamp: 1
        )
    }
}

@MainActor
private final class RecordingPointerSketch: P5Sketch {
    private(set) var receivedPhases: [P5PointerPhase] = []

    override func pointerEntered(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerExited(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerMoved(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerDragged(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerPressed(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerReleased(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerClicked(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
    override func pointerCancelled(_ event: P5PointerEvent) { receivedPhases.append(event.phase) }
}
