import CoreGraphics
import Foundation
import Testing

@testable import P5

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
@Suite("P5 native interaction hooks", .serialized)
struct P5InteractionTests {
    @Test("Focus, hover, scroll, drop, and accessibility values dispatch in order")
    func deliveryAndState() throws {
        let sketch = RecordingInteractionSketch(size: CGSize(width: 100, height: 80))
        let canvas = try #require(sketch.view as? P5SketchInternalView)

        for (index, cause) in P5FocusCause.allCases.enumerated() {
            sketch.injectFocusEvent(
                P5FocusEvent(
                    isFocused: index.isMultiple(of: 2),
                    cause: cause,
                    timestamp: TimeInterval(index)
                )
            )
        }
        #expect(sketch.focusStates == [true, false, true, false])
        #expect(sketch.isFocused == false)
        #expect(sketch.latestFocusEvent?.cause == .system)

        let hoverPhases = P5HoverPhase.allCases
        for (index, phase) in hoverPhases.enumerated() {
            sketch.injectHoverEvent(
                P5HoverEvent(
                    phase: phase,
                    location: CGPoint(x: index, y: index + 1),
                    timestamp: TimeInterval(index)
                )
            )
        }
        #expect(sketch.hoverPhases == hoverPhases)
        #expect(sketch.isHovered == false)

        for (index, phase) in P5ScrollPhase.allCases.enumerated() {
            sketch.injectScrollEvent(
                P5ScrollEvent(
                    phase: phase,
                    delta: CGVector(dx: index, dy: -index),
                    location: CGPoint(x: 2, y: 3),
                    modifiers: [.option],
                    isPrecise: true,
                    isDirectionInverted: true,
                    isMomentum: index > 0,
                    timestamp: TimeInterval(index)
                )
            )
        }
        #expect(sketch.scrollPhases == P5ScrollPhase.allCases)
        #expect(sketch.latestScrollEvent?.isPrecise == true)

        let payloads: [P5DropPayload] = [
            .file(URL(fileURLWithPath: "/tmp/p5-drop.txt")),
            .text("drop"),
            .data(Data([1, 2, 3]), typeIdentifier: "public.data"),
        ]
        for (index, phase) in P5DropPhase.allCases.enumerated() {
            sketch.injectDropEvent(
                P5DropEvent(
                    phase: phase,
                    location: CGPoint(x: index, y: 4),
                    payloads: payloads,
                    timestamp: TimeInterval(index)
                )
            )
        }
        #expect(sketch.dropPhases == P5DropPhase.allCases)
        #expect(sketch.latestDropEvent?.payloads == payloads)

        let actions: [P5AccessibilityAction] = [
            .activate, .increment, .decrement, .escape, .custom("shuffle"),
        ]
        for (index, action) in actions.enumerated() {
            let handled = sketch.performAccessibilityAction(
                P5AccessibilityEvent(action: action, timestamp: TimeInterval(index))
            )
            #expect(handled == (action == .activate))
        }
        #expect(sketch.accessibilityActions == actions)
        #expect(sketch.latestAccessibilityEvent?.action == .custom("shuffle"))

        canvas.deliverFocusEvent(P5FocusEvent(isFocused: true, cause: .system, timestamp: 10))
        canvas.deliverScrollEvent(
            P5ScrollEvent(
                phase: .changed,
                delta: CGVector(dx: 1, dy: 2),
                location: .zero,
                timestamp: 10
            )
        )
        #expect(sketch.isFocused)
        #expect(sketch.latestScrollEvent?.delta == CGVector(dx: 1, dy: 2))
    }

    #if canImport(AppKit)
        @Test(
            "Pointer hover, native focus, scroll mapping, and accessibility metadata bridge AppKit")
        func appKitAdapters() throws {
            let sketch = RecordingInteractionSketch(size: CGSize(width: 40, height: 30))
            let canvas = try #require(sketch.view as? P5SketchInternalView)

            for phase in P5PointerPhase.allCases {
                canvas.deliverPointerEvent(
                    P5PointerEvent(
                        id: 0,
                        kind: .mouse,
                        phase: phase,
                        location: CGPoint(x: 4, y: 5),
                        previousLocation: CGPoint(x: 3, y: 5),
                        timestamp: 1
                    )
                )
            }
            canvas.deliverPointerEvent(
                P5PointerEvent(
                    id: 8,
                    kind: .indirect,
                    phase: .moved,
                    location: .zero,
                    previousLocation: .zero,
                    timestamp: 2
                )
            )
            canvas.deliverPointerEvent(
                P5PointerEvent(
                    id: 9,
                    kind: .touch,
                    phase: .entered,
                    location: .zero,
                    previousLocation: .zero,
                    timestamp: 2
                )
            )
            #expect(sketch.hoverPhases == [.entered, .exited, .moved, .moved])

            #expect(sketch.requestFocus() == false)
            _ = canvas.becomeFirstResponder()
            _ = canvas.resignFirstResponder()
            #expect(sketch.latestFocusEvent?.isFocused == false)

            #expect(P5SketchInternalView.scrollPhase(phase: .began, momentumPhase: []) == .began)
            #expect(P5SketchInternalView.scrollPhase(phase: .ended, momentumPhase: []) == .ended)
            #expect(
                P5SketchInternalView.scrollPhase(phase: .cancelled, momentumPhase: []) == .cancelled
            )
            #expect(P5SketchInternalView.scrollPhase(phase: [], momentumPhase: []) == .changed)
            #expect(
                P5SketchInternalView.scrollPhase(phase: .began, momentumPhase: .ended) == .ended
            )
            let cgEvent = try #require(
                CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .pixel,
                    wheelCount: 2,
                    wheel1: 2,
                    wheel2: 1,
                    wheel3: 0
                )
            )
            let nativeScroll = try #require(NSEvent(cgEvent: cgEvent))
            canvas.scrollWheel(with: nativeScroll)
            #expect(sketch.latestScrollEvent != nil)

            sketch.accessibilityLabel = "Particle canvas"
            sketch.accessibilityValue = "12 particles"
            sketch.accessibilityHint = "Press to reset"
            #expect(canvas.isAccessibilityElement())
            #expect(canvas.accessibilityLabel() == "Particle canvas")
            #expect(canvas.accessibilityValue() as? String == "12 particles")
            #expect(canvas.accessibilityHelp() == "Press to reset")
            sketch.accessibilityLabel = nil
            sketch.accessibilityValue = nil
            sketch.accessibilityHint = nil
            #expect(canvas.isAccessibilityElement() == false)

            #expect(canvas.accessibilityPerformPress())
            #expect(canvas.accessibilityPerformIncrement() == false)
            #expect(canvas.accessibilityPerformDecrement() == false)
            #expect(canvas.accessibilityPerformCancel() == false)
            #expect(
                sketch.accessibilityActions.suffix(4) == [
                    .activate, .increment, .decrement, .escape,
                ]
            )
        }
    #endif

    @Test("Interaction values serialize and reject corrupted recordings")
    func serialization() throws {
        let focus = P5FocusEvent(isFocused: true, cause: .keyboard, timestamp: 101)
        let hover = P5HoverEvent(
            phase: .moved,
            location: CGPoint(x: 1, y: 2),
            modifiers: [.shift],
            timestamp: 102
        )
        let scroll = P5ScrollEvent(
            phase: .changed,
            delta: CGVector(dx: 3, dy: 4),
            location: CGPoint(x: 5, y: 6),
            isPrecise: true,
            isDirectionInverted: true,
            isMomentum: true,
            timestamp: 103
        )
        let drop = P5DropEvent(
            phase: .performed,
            location: CGPoint(x: 7, y: 8),
            payloads: [.text("hello")],
            timestamp: 104
        )
        let accessibility = P5AccessibilityEvent(action: .activate, timestamp: 105)

        try roundTrip(focus)
        try roundTrip(hover)
        try roundTrip(scroll)
        try roundTrip(drop)
        try roundTrip(accessibility)
        for (value, timestamp) in [
            (focus, 101), (hover, 102), (scroll, 103), (drop, 104), (accessibility, 105),
        ] as [(any Encodable, Int)] {
            let encoded = try JSONEncoder().encode(AnyEncodable(value))
            let json = try #require(String(data: encoded, encoding: .utf8))
            let invalid = Data(
                json.replacingOccurrences(
                    of: "\"timestamp\":\(timestamp)",
                    with: "\"timestamp\":-1"
                ).utf8
            )
            switch timestamp {
            case 101:
                #expect(throws: DecodingError.self) {
                    _ = try JSONDecoder().decode(P5FocusEvent.self, from: invalid)
                }
            case 102:
                #expect(throws: DecodingError.self) {
                    _ = try JSONDecoder().decode(P5HoverEvent.self, from: invalid)
                }
            case 103:
                #expect(throws: DecodingError.self) {
                    _ = try JSONDecoder().decode(P5ScrollEvent.self, from: invalid)
                }
            case 104:
                #expect(throws: DecodingError.self) {
                    _ = try JSONDecoder().decode(P5DropEvent.self, from: invalid)
                }
            default:
                #expect(throws: DecodingError.self) {
                    _ = try JSONDecoder().decode(P5AccessibilityEvent.self, from: invalid)
                }
            }
        }
    }

    #if canImport(AppKit)
        @Test("A scoped clipboard supports text, typed data, and explicit clearing")
        func clipboard() {
            let generalClipboard = P5Clipboard.general
            #expect(generalClipboard === P5Clipboard.general)

            let pasteboard = NSPasteboard(name: NSPasteboard.Name("P5Tests.\(UUID().uuidString)"))
            let clipboard = P5Clipboard(pasteboard: pasteboard)
            defer { clipboard.clear() }
            clipboard.setText("native clipboard")
            #expect(clipboard.text == "native clipboard")
            clipboard.setData(Data([4, 5, 6]), forTypeIdentifier: "public.data")
            #expect(clipboard.data(forTypeIdentifier: "public.data") == Data([4, 5, 6]))
            clipboard.clear()
            #expect(clipboard.text == nil)
        }
    #endif

    @Test("Base interaction hooks are safe no-ops")
    func baseHooks() throws {
        let sketch = P5Sketch(size: CGSize(width: 10, height: 10))
        let canvas = try #require(sketch.view as? P5SketchInternalView)
        sketch.injectFocusEvent(P5FocusEvent(isFocused: true, cause: .programmatic, timestamp: 0))
        sketch.injectFocusEvent(P5FocusEvent(isFocused: false, cause: .programmatic, timestamp: 0))
        for phase in P5HoverPhase.allCases {
            sketch.injectHoverEvent(P5HoverEvent(phase: phase, location: .zero, timestamp: 0))
        }
        sketch.injectScrollEvent(
            P5ScrollEvent(phase: .changed, delta: .zero, location: .zero, timestamp: 0)
        )
        sketch.injectDropEvent(
            P5DropEvent(phase: .cancelled, location: .zero, timestamp: 0)
        )
        #expect(
            sketch.performAccessibilityAction(
                P5AccessibilityEvent(action: .escape, timestamp: 0)
            ) == false
        )
        #if canImport(AppKit)
            #expect(canvas.accessibilityPerformPress() == false)
        #else
            #expect(canvas.accessibilityActivate() == false)
        #endif

        var releasedSketch: P5Sketch? = P5Sketch(size: CGSize(width: 10, height: 10))
        let releasedCanvas = try #require(releasedSketch?.view as? P5SketchInternalView)
        releasedSketch = nil
        #expect(releasedCanvas.deliverAccessibilityAction(.activate) == false)
    }

    @Test("Invalid interaction values terminate at public boundaries")
    nonisolated func invalidValuesTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5FocusEvent(isFocused: true, cause: .system, timestamp: -1)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5HoverEvent(
                    phase: .moved,
                    location: CGPoint(x: CGFloat.nan, y: 0),
                    timestamp: 0
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5ScrollEvent(
                    phase: .changed,
                    delta: CGVector(dx: CGFloat.infinity, dy: 0),
                    location: .zero,
                    timestamp: 0
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5DropEvent(
                    phase: .updated,
                    location: .zero,
                    timestamp: .nan
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5AccessibilityEvent(action: .activate, timestamp: .nan)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Clipboard.general.data(forTypeIdentifier: "")
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Clipboard.general.setData(Data(), forTypeIdentifier: "")
                }
            }
        #endif
    }

    private func roundTrip<Value>(_ value: Value) throws
    where Value: Codable & Equatable {
        #expect(try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value)) == value)
    }
}

private struct AnyEncodable: Encodable {
    let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

@MainActor
private final class RecordingInteractionSketch: P5Sketch {
    private(set) var focusStates: [Bool] = []
    private(set) var hoverPhases: [P5HoverPhase] = []
    private(set) var scrollPhases: [P5ScrollPhase] = []
    private(set) var dropPhases: [P5DropPhase] = []
    private(set) var accessibilityActions: [P5AccessibilityAction] = []

    override func focusChanged(_ event: P5FocusEvent) {}
    override func focusGained(_ event: P5FocusEvent) { focusStates.append(true) }
    override func focusLost(_ event: P5FocusEvent) { focusStates.append(false) }
    override func hoverChanged(_ event: P5HoverEvent) {}
    override func hoverEntered(_ event: P5HoverEvent) { hoverPhases.append(event.phase) }
    override func hoverMoved(_ event: P5HoverEvent) { hoverPhases.append(event.phase) }
    override func hoverExited(_ event: P5HoverEvent) { hoverPhases.append(event.phase) }
    override func scrolled(_ event: P5ScrollEvent) { scrollPhases.append(event.phase) }
    override func dropChanged(_ event: P5DropEvent) { dropPhases.append(event.phase) }

    override func accessibilityAction(_ event: P5AccessibilityEvent) -> Bool {
        accessibilityActions.append(event.action)
        return event.action == .activate
    }
}
